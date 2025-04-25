#!/bin/bash
dialog --msgbox "Read this script carefully before use it, "\
"this only works with uefi bios" 0 0

clear

root_pw=$(dialog --insecure --passwordbox "enter root password" 0 0 --output-fd 1)

username=$(dialog --inputbox "enter username" 0 0 --output-fd 1)

user_pw=$(dialog --insecure --passwordbox "enter user password" 0 0 --output-fd 1)

luks_pw=$(dialog --insecure --passwordbox "enter luks password" 0 0 --output-fd 1)


user_groups="wheel,audio,video,cdrom,optical,kvm,xbuilder"

efi_part_size=$(dialog --inputbox "enter efi partition size (for example: 512M" 0 0 --output-fd 1)

root_part_size=$(dialog --inputbox "enter root partition size (for example: 40G)" 0 0 --output-fd 1)

# if it is empty it will create only a root partition. (and doesnt create a home partition with the remaining space)

hostname=$(dialog --inputbox "enter hostname" 0 0 --output-fd 1)

fs_type=$(dialog --inputbox "enter partition file system type (possible values are: xfs or ext4)" 0 0 --output-fd 1) #support ext4 or xfs

libc=$(dialog --inputbox "enter musl or leave empty for glibc install" 0 0 --output-fd 1) #empty is glibc other value is musl

language="en_US.UTF-8"

graphical=$(dialog --inputbox "enter graphical interface: (possible values are: gnome, kde or empty for minimal installation" 0 0 --output-fd 1)
#empty it will install only base system and apps_minimal or kde or gnome

disk=$(dialog --inputbox "enter disk for installation (for example: /dev/sda or /dev/vda for virt-manager" 0 0 --output-fd 1) #or /dev/vda for virt-manager


secure_boot=$(dialog --inputbox "enable secure boot? (possible values: yes or no) note: you can break your bios" 0 0 --output-fd 1)
# better leave this empty you can break your bios / secure boot in the bios must be in setup mode / yes or empty for disable
clear

void_repo="https://repo-fastly.voidlinux.org"
#after install change mirror with xmirror

ARCH="x86_64"

#dns_list=("9.9.9.9" "1.1.1.1")

apps="xorg-minimal dejavu-fonts-ttf nano elogind dbus socklog-void apparmor chrony unrar"\
" xdg-desktop-portal xdg-user-dirs xdg-desktop-portal-gtk xdg-utils xmirror terminus-font"\
" fastfetch pipewire wireplumber font-adobe-source-code-pro ttf-ubuntu-font-family ufw gufw"\
" nftables iptables-nft vsv htop opendoas topgrade octoxbps flatpak"

apps_optional="lynis lm_sensors hplip ffmpeg bash-completion" 

apps_intel="mesa-dri intel-ucode intel-gpu-tools vulkan-loader mesa-vulkan-intel intel-video-accel"

apps_kde="kde-plasma kde-baseapps ark print-manager spectacle kdeconnect okular"\
" skanlite gwenview kwalletmanager sddm-kcm partitionmanager kcalc plasma-disks ffmpegthumbs NetworkManager octoxbps"

apps_gnome="gnome-core gnome-console gnome-tweaks gnome-browser-connector gnome-text-editor NetworkManager"

ignore_pkgs=("sudo" "linux-firmware-amd" "linux-firmware-nvidia" "linux-firmware-broadcom")

#for test
apps_minimal="nano apparmor vsv opendoas iwd terminus-font"

rm_services=("agetty-tty3" "agetty-tty4" "agetty-tty5" "agetty-tty6")
en_services=("acpid" "dbus" "chronyd" "udevd" "uuidd" "cupsd" "socklog-unix" "nanoklogd" "NetworkManager" "ufw" "sddm" "gdm")


if [[ $disk == *"sd"* ]]; then
	efi_part=$(echo $disk'1')
	luks_part=$(echo $disk'2')
elif [[ $disk == *"vd"* ]]; then
	efi_part=$(echo $disk'1')
	luks_part=$(echo $disk'2')
elif [[ $disk == *"nvme"* ]]; then
	efi_part=$(echo $disk'p1')
	luks_part=$(echo $disk'p2')
fi

#Wipe disk
wipefs -aq $disk

#dd if=/dev/zero of=/dev$disk bs=16M count=500

printf 'label: gpt\n, %s, U, *\n, , L\n' "$efi_part_size" | sfdisk -q "$disk"

#Create LUKS2 encrypted partition
#cryptsetup benchmark   to find the best cypher for your pc
echo $luks_pw | cryptsetup -q luksFormat $luks_part
echo $luks_pw | cryptsetup --type luks2 open $luks_part cryptroot
vgcreate $hostname /dev/mapper/cryptroot

if [[ -z $root_part_size  ]]; then

	lvcreate --name root -l 100%FREE $hostname
else
	lvcreate --name root -L $root_part_size $hostname
	lvcreate --name home -l 100%FREE $hostname
fi


mkfs.$fs_type -qL root /dev/$hostname/root
if [[ ! -z $root_part_size ]]; then

	mkfs.$fs_type -qL home /dev/$hostname/home
fi


mount /dev/$hostname/root /mnt

for dir in dev proc sys run; do

	mkdir -p /mnt/$dir
	mount --rbind /$dir /mnt/$dir
	mount --make-rslave /mnt/$dir
done


  if [[ ! -z $root_part_size ]]; then
	mkdir -p /mnt/home
	mount /dev/$hostname/home /mnt/home
fi
	mkfs.vfat $efi_part
	mkdir -p /mnt/efi
	mount $efi_part /mnt/efi


mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/
echo y | XBPS_ARCH=$ARCH xbps-install -SyR $void_repo/current/$libc -r /mnt base-system cryptsetup lvm2 efibootmgr dracut-uefi gummiboot-efistub sbctl


#luks_uuid=$(blkid -o value -s UUID $luks_part)

chroot /mnt chown root:root /
chroot /mnt chmod 755 /

chroot /mnt useradd -m -g users -G $user_groups $username -s /bin/bash


cat << EOF | chroot /mnt
echo "$root_pw\n$root_pw" | passwd -q root
echo "$user_pw\n$user_pw" | passwd -q $username
EOF

#Set hostname and language/locale
echo $hostname > /mnt/etc/hostname


if [[ -z $libc ]]; then
    echo "LANG=$language" > /mnt/etc/locale.conf
    echo -e "pt_PT.UTF-8 UTF-8  
             pt_PT ISO-8859-1  
             pt_PT@euro ISO-8859-15" >> /mnt/etc/default/libc-locales
    xbps-reconfigure -fr /mnt/ glibc-locales
fi

chroot /mnt/ ln -sf /usr/share/zoneinfo/Europe/Lisbon /etc/localtime

luks_root_uuid=$(blkid -o value -s UUID  /mnt/dev/mapper/$hostname-root)
luks_home_uuid=$(blkid -o value -s UUID  /mnt/dev/mapper/$hostname-home)
boot_uuid=$(blkid -o value -s UUID  /mnt$disk'1')

echo -e "UUID=$luks_root_uuid	/	$fs_type	defaults,noatime	0	1" >> /mnt/etc/fstab
if [[ ! -z $root_part_size ]]; then

	echo -e "UUID=$luks_home_uuid	/home	$fs_type	defaults,noatime	0	2" >> /mnt/etc/fstab
fi

	echo -e "UUID=$boot_uuid	  /efi	    vfat	umask=0077	0	2" >> /mnt/etc/fstab

	
#add hostonly to dracut
echo "hostonly=yes" >> /mnt/etc/dracut.conf.d/10-boot.conf
echo 'uefi="yes"' >>  /mnt/etc/dracut.conf.d/10-boot.conf
echo "uefi_stub=/usr/lib/gummiboot/linuxx64.efi.stub" >> /mnt/etc/dracut.conf.d/10-boot.conf
echo 'kernel_cmdline="quiet lsm=capability,landlock,yama,apparmor rd.luks.name='$luks_root_uuid'=cryptroot rd.lvm.vg='$hostname 'root=/dev/'$hostname'/root rd.luks.allow-discards"' >> /mnt/etc/dracut.conf.d/10-boot.conf
echo 'early_microcode="yes"' >> /mnt/etc/dracut.conf.d/10-boot.conf

# harden sysctl

mkdir /mnt/etc/sysctl.d
touch /mnt/etc/sysctl.d/10-void-user.conf


echo -e "kernel.dmesg_restrict=1
kernel.kexec_load_disabled=1
kernel.yama.ptrace_scope=2
kernel.kptr_restrict=2
kernel.printk=3 3 3 3
kernel.unprivileged_bpf_disabled=1
net.core.bpf_jit_harden=2
dev.tty.ldisc_autoload=0
vm.unprivileged_userfaultfd=0
kernel.sysrq=4
kernel.unprivileged_userns_clone=0
kernel.perf_event_paranoid=3
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_rfc1337=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.icmp_echo_ignore_all=1
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.default.accept_source_route=0
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.default.accept_ra=0
net.ipv4.tcp_sack=0
net.ipv4.tcp_dsack=0
net.ipv4.tcp_fack=0
vm.mmap_rnd_bits=32
vm.mmap_rnd_compat_bits=16
fs.protected_symlinks=1
fs.protected_hardlinks=1
fs.protected_fifos=2
fs.protected_regular=2" > /mnt/etc/sysctl.d/10-void-user.conf

#secure boot
if [[ ! -z $secure_boot ]]; then

chroot /mnt sbctl create-keys
chroot /mnt sbctl enroll-keys -m -i #this use microsoft keys to uefi secure boot
fi

echo "CREATE_UEFI_BUNDLES=yes" >> /mnt/etc/default/dracut-uefi-hook
echo 'UEFI_BUNDLE_DIR="efi/EFI/Linux/"' >> /mnt/etc/default/dracut-uefi-hook

mkdir -p /mnt/efi/EFI/Linux

xbps-install -SuyR $void_repo/current/$libc -r /mnt xbps
xbps-install -SyR $void_repo/current/$libc -r /mnt void-repo-nonfree

if [[ $graphical == "kde" ]]; then
xbps-install -SyR $void_repo/current/$libc -r /mnt $apps $apps_kde $apps_intel $apps_optional

elif [[ $graphical == "gnome" ]]; then
xbps-install -SyR $void_repo/current/$libc -r /mnt $apps $apps_gnome $apps_intel $apps_optional

else
xbps-install -SyR $void_repo/current/$libc -r /mnt $apps_minimal
fi


if [[ $graphical != "" ]]; then

#pipewire
chroot /mnt mkdir -p /etc/pipewire/pipewire.conf.d
chroot /mnt ln -s /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
chroot /mnt ln -s /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/

#start pipewire.desktop for kde gnome etc 
chroot /mnt ln -s /usr/share/applications/pipewire.desktop /etc/xdg/autostart/pipewire.desktop

#octoxbps-notifier
chroot /mnt ln -s /usr/share/applications/octoxbps-notifier.desktop /etc/xdg/autostart/octoxbps-notifier.desktop

for serv1 in ${rm_services[@]}; do

	chroot /mnt unlink /var/service/$serv1
done

for serv2 in ${en_services[@]}; do

	chroot /mnt ln -s /etc/sv/$serv2 /var/service
	
done
fi


touch /mnt/etc/kernel.d/post-install/10-uefi-boot
echo "#!/bin/sh" > /mnt/etc/kernel.d/post-install/10-uefi-boot
echo "mv /efi/EFI/Linux/linux-* /efi/EFI/Linux/linuxOLD.efi" >> /mnt/etc/kernel.d/post-install/10-uefi-boot
chmod +x /mnt/etc/kernel.d/post-install/10-uefi-boot

touch /mnt/etc/kernel.d/post-install/99-uefi-boot
echo "#!/bin/sh" > /mnt/etc/kernel.d/post-install/99-uefi-boot
echo "cp /efi/EFI/Linux/linux-* /efi/EFI/Linux/linux.efi" >> /mnt/etc/kernel.d/post-install/99-uefi-boot
echo "sbctl sign -s /efi/EFI/Linux/linux.efi" >> /mnt/etc/kernel.d/post-install/99-uefi-boot
chmod +x /mnt/etc/kernel.d/post-install/99-uefi-boot

#rc.conf
echo 'KEYMAP="uk"' >> /mnt/etc/rc.conf
echo 'FONT="ter-v22n"' >> /mnt/etc/rc.conf



#apparmor
sed -i 's/^#*APPARMOR=.*$/APPARMOR=enforce/i' /mnt/etc/default/apparmor
sed -i 's/^#*write-cache/write-cache/i' /mnt/etc/apparmor/parser.conf


chroot /mnt touch /home/$username/.bash_aliases
chroot /mnt chown $username:$username /home/$username/.bash_aliases

echo -e "source /home/$username/.bash_aliases
fastfetch
complete -cf xi xs" >> /mnt/home/$username/.bashrc


echo -e "alias xi='doas xbps-install -S' 
alias xu='doas xbps-install -Suy'
alias xs='xbps-query -Rs'
alias xr='doas xbps-remove -oOR'
alias xq='xbps-query'
alias xsi='xbps-query -m'
alias sudo='doas'
alias dmesg='doas dmesg'
alias logs='doas svlogtail'
alias e='nano'
alias de='doas nano'
alias vsv='doas vsv'
alias reboot='doas reboot'
alias poweroff='doas poweroff'
alias net='ss -atup'" >> /mnt/home/$username/.bash_aliases

#fonts
chroot /mnt ln -s /usr/share/fontconfig/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/
#xbps-reconfigure -fr fontconfig /mnt/

#doas
echo "permit persist setenv {PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin} :wheel" > /mnt/etc/doas.conf
chroot /mnt chown -c root:root /etc/doas.conf
chroot /mnt chmod -c 0400 /etc/doas.conf

mkdir /mnt/etc/iwd
touch /mnt/etc/iwd/main.conf
echo -e "[General]
EnableNetworkConfiguration=true
[Network]
RoutePriorityOffset=200
NameResolvingService=none
EnableIPv6=false" >> /mnt/etc/iwd/main.conf


#time zone
chroot /mnt ln -sf /usr/share/zoneinfo/Europe/Lisbon /etc/localtime

#ignore packages
chroot /mnt touch /etc/xbps.d/99-ignorepkgs.conf

for pkg in ${ignore_pkgs[@]}; do

  echo "ignorepkg="$pkg >> /mnt/etc/xbps.d/99-ignorepkgs.conf
  chroot /mnt xbps-remove -oOR $pkg -y	
done



#dns
#for dns in ${dns_list[@]}; do

  #echo "nameserver="$dns >> /mnt/etc/resolv.conf
  	
#done

xbps-reconfigure -far /mnt/ 


efibootmgr -c -d $disk -p 1 -L "Void Linux" -l "\EFI\Linux\linux.efi"
efibootmgr -c -d $disk -p 1 -L "Void Linux OLD" -l "\EFI\Linux\linuxOLD.efi"

echo -e "\nUnmount Void installation and reboot?(y/n)\n"
read tmp
if [[ $tmp == "y" ]]; then
	umount -R /mnt
 	reboot 
  shutdown -r now
fi

echo -e "\nFinish\n"
