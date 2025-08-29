#!/bin/bash

dialog --msgbox "Disclaimer: Read the script carefully before use it, i am not responsible for any damage or loss "\
"of data caused by it. Everyone can use it and change it. Works with uefi and its configured for intel graphics, for "\ "nvidia you must add packages to it. The install uses disk encryption with luks2 by default, if you set root partition "\ "size empty it will use all disk space, if you leave it by default (25G) it will use the remaining space for a home "\ "partition. This is valid for xfs and ext4, for btrfs you must set root partition size empty. For swap i use zramen."\
"For backups i use Timeshift with grub and grub-btrfs."\
"This help me to automate my custom installation of Void Linux. There is a lot of customization and some bugs..."\
"Notes: Grub with secure boot (sbctl) doesnt work (for now), grub-btrfs only populate grub menu with snapshots after "\ "grub-update."\
"Read it before installation, its easy to adapt to other preferences." 0 0 --output-fd 1

clear

dialog --yesno "Proceed to installation?" 0 0 --output-fd 1
start=$?
clear

if [[ $start == 1 ]]; then
	exit
fi


root_pw=$(dialog --insecure --passwordbox "enter root password" 0 0 --output-fd 1)

username=$(dialog --inputbox "enter username" 0 0 --output-fd 1)

user_pw=$(dialog --insecure --passwordbox "enter user password" 0 0 --output-fd 1)

luks_pw=$(dialog --insecure --passwordbox "enter luks password" 0 0 --output-fd 1)

user_groups="wheel,audio,video,kvm,xbuilder"

efi_part_size=$(dialog --inputbox "enter efi partition size (default: 512M)" 0 0 512M --output-fd 1)

root_part_size=$(dialog --inputbox "enter root partition size (default: 25G)" 0 0 25G --output-fd 1)

hostname=$(dialog --inputbox "enter your hostname" 0 0 xpt099 --output-fd 1)

fs_type=$(dialog --radiolist "choose your file system" 0 0 3 'xfs' 1 on 'ext4' 2 off 'btrfs' 3 off --output-fd 1) 

glib=$(dialog --radiolist "choose btw glibc or musl" 0 0 2 'glibc' 1 on 'musl' 2 off --output-fd 1 )

if [[ $glib == "glibc" ]]; then
	glib=""
fi

language="en_US.UTF-8"

bm=$(dialog --radiolist "choose your boot manager" 0 0 3 'grub' 1 on 'efistub' 2 off 'refind' 3 off --output-fd 1)

graphical=$(dialog --radiolist "choose your graphical interface" 0 0 3 'kde' 1 on 'gnome' 2 off 'xfce' 3 off 'minimal' 4 off --output-fd 1)

if [[ $graphical == "minimal" ]]; then
	graphical=""
fi

disk=$(dialog --radiolist "enter disk for installation" 0 0 3 '/dev/sda' 1 on '/dev/vda' 2 off '/dev/nvme0n1' 3 off --output-fd 1)


dialog --yesno "enable secure boot?" 0 0 --output-fd 1

secure_boot=$?

clear

ARCH="x86_64"

if [[ $glib == "musl" ]]; then

	ARCH="x86_64-musl"

fi

void_repo="https://repo-de.voidlinux.org/current/"$glib
#after install change mirror with xmirror

#dns_list=("9.9.9.9" "1.1.1.1")


apps="nano neovim elogind dbus socklog-void apparmor chrony xmirror fastfetch pipewire wireplumber"\
" nftables runit-nftables vsv htop btop bat opendoas topgrade octoxbps flatpak zramen"\
" earlyoom irqbalance ffmpeg bash-completion lm_sensors"

apps_optional="lynis hplip hplip-gui starship"

apps_intel="mesa-dri intel-ucode intel-gpu-tools intel-video-accel"

if [[ $disk == "/dev/vda" ]]; then #virtual machine

	apps_intel="xf86-video-qxl"
	apps_optional=""
	apps="nano dbus socklog-void fastfetch pipewire wireplumber vsv htop bat opendoas"
fi

apps_kde="kde-plasma kde-baseapps discover ffmpegthumbs NetworkManager discover spectacle flatpack-kcm gparted"

apps_gnome="gnome-core gnome-console gnome-tweaks gnome-browser-connector gnome-text-editor NetworkManager"

apps_xfce="xfce4 paper-gtk-theme paper-icon-theme xorg-minimal lightdm xfce4-pulseaudio-plugin xfce4-whiskermenu-plugin"\
" NetworkManager labwc"

fonts="font-adobe-source-code-pro ttf-ubuntu-font-family terminus-font dejavu-fonts-ttf"
#for test
apps_minimal="nano vsv opendoas iwd terminus-font bat"

rm_services=("agetty-tty3" "agetty-tty4" "agetty-tty5" "agetty-tty6")

en_services=("acpid" "dbus" "chronyd" "udevd" "uuidd" "cupsd" "socklog-unix" "nanoklogd" "NetworkManager" "iwd" "nftables"  "sddm" "gdm" "lightdm" "zramen" "earlyoom" "irqbalance" "grub-btrfs" "dhcpcd-eth0")


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


dialog --yesno "we are about to format the disk, do you want to proceed?" 0 0 --output-fd 1
begin=$?
clear

if [[ $begin == 0 ]]; then
#dd if=/dev/urandom of=$disk count=100000 status=progress
#Wipe disk
	wipefs -aq $disk
	else exit
fi
#dd if=/dev/zero of=/dev$disk bs=16M count=500

printf 'label: gpt\n, %s, U, *\n, , L\n' "$efi_part_size" | sfdisk -q "$disk"

#Create LUKS2 encrypted partition
#cryptsetup benchmark   to find the best cypher for your pc

if [[ $bm == "grub" ]]; then
	echo $luks_pw | cryptsetup -q luksFormat $luks_part --pbkdf pbkdf2
	echo $luks_pw | cryptsetup open $luks_part cryptroot
else
	echo $luks_pw | cryptsetup -q luksFormat $luks_part
	echo $luks_pw | cryptsetup open $luks_part cryptroot
fi

if [[ $fs_type != "btrfs"  ]]; then
vgcreate $hostname /dev/mapper/cryptroot


	if [[ -z $root_part_size  ]]; then

		lvcreate --name root -l 100%FREE $hostname
	else
		lvcreate --name root -L $root_part_size $hostname
		lvcreate --name home -l 100%FREE $hostname
	fi
else
	mkfs.btrfs -L $hostname /dev/mapper/cryptroot

fi

if [[ $fs_type != "btrfs"  ]]; then
	mkfs.$fs_type -qL root /dev/$hostname/root
fi

if [[ $fs_type != "btrfs"  ]]; then
	if [[ ! -z $root_part_size ]]; then

		mkfs.$fs_type -qL home /dev/$hostname/home
	fi
else
	BTRFS_OPTS="compress=zstd,noatime,space_cache=v2,discard,ssd"
	mount -o $BTRFS_OPTS /dev/mapper/cryptroot /mnt
	btrfs subvolume create /mnt/@
	btrfs subvolume create /mnt/@home
	#btrfs subvolume create /mnt/@snapshots
    umount /mnt
fi

if [[ $fs_type != "btrfs"  ]]; then
	mount /dev/$hostname/root /mnt
else
	mount -o $BTRFS_OPTS,subvol=@ /dev/mapper/cryptroot /mnt
	mkdir -p /mnt/home
	mount -o $BTRFS_OPTS,subvol=@home /dev/mapper/cryptroot /mnt/home
	#mkdir -p /mnt/.snapshots
	#mount -o $BTRFS_OPTS,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
	mkdir -p /mnt/var/cache
	btrfs subvolume create /mnt/var/cache/xbps
	btrfs subvolume create /mnt/var/tmp
	btrfs subvolume create /mnt/srv
fi

 for dir in dev proc sys run; do

 	mkdir -p /mnt/$dir
 	mount --rbind /$dir /mnt/$dir
 	mount --make-rslave /mnt/$dir
 done


if [[ $fs_type != "btrfs"  ]]; then
  if [[ ! -z $root_part_size ]]; then
	mkdir -p /mnt/home
	mount /dev/$hostname/home /mnt/home
  fi
fi
	mkfs.vfat $efi_part
	mkdir -p /mnt/efi
	mount $efi_part /mnt/efi

mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/

if [[ $bm == "grub" ]]; then
echo y | XBPS_ARCH=$ARCH xbps-install -SyR $void_repo -r /mnt base-system cryptsetup zstd lvm2 efibootmgr sbsigntool sbctl grub grub-btrfs grub-btrfs-runit btrfs-progs grub-x86_64-efi timeshift

else

echo y | XBPS_ARCH=$ARCH xbps-install -SyR $void_repo -r /mnt base-system cryptsetup zstd lvm2 efibootmgr sbsigntool systemd-boot-efistub sbctl refind dracut-uefi
chroot /mnt xbps-alternatives -s dracut-uefi
fi

#CHROOT
cat << EOF | xchroot /mnt /bin/bash

chown root:root /
chmod 755 /

useradd -m -U -G $user_groups $username -s /bin/bash


echo "$root_pw\n$root_pw" | passwd -q root
echo "$user_pw\n$user_pw" | passwd -q $username


#Set hostname and language/locale
echo $hostname > /etc/hostname


if [[ -z $glib ]]; then
    echo "LANG=$language" > /etc/locale.conf
    echo -e "pt_PT.UTF-8 UTF-8
             pt_PT ISO-8859-1
             pt_PT@euro ISO-8859-15" >> /etc/default/libc-locales
    xbps-reconfigure -fr glibc-locales
fi

ln -sf /usr/share/zoneinfo/Europe/Lisbon /etc/localtime


luks_root_uuid=$(blkid -o value -s UUID  /dev/mapper/$hostname-root)
luks_home_uuid=$(blkid -o value -s UUID  /dev/mapper/$hostname-home)
boot_uuid=$(blkid -o value -s UUID  $disk'1')
luks_uuid=$(blkid -o value -s UUID  $disk'2')
ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)

if [[ $fs_type != "btrfs"  ]]; then
	echo -e "UUID=$luks_root_uuid	/	$fs_type	defaults,noatime	0	1" >> /etc/fstab
	if [[ ! -z $root_part_size ]]; then

		echo -e "UUID=$luks_home_uuid	/home	$fs_type	defaults,noatime	0	2" >> /etc/fstab
	fi
else
	echo -e "UUID=$ROOT_UUID / btrfs $BTRFS_OPTS,subvol=@ 0 1
	UUID=$ROOT_UUID /home btrfs $BTRFS_OPTS,subvol=@home 0 2" >> /etc/fstab
fi

echo -e "UUID=$boot_uuid	  /efi	    vfat	umask=0077	0	2
efivarfs /sys/firmware/efi/efivars efivarfs defaults 0 0" >> /etc/fstab


	#dracut
echo "hostonly=yes" >> /etc/dracut.conf.d/10-boot.conf
if [[ $bm != "grub" ]]; then
	echo 'uefi="yes"' >>  /etc/dracut.conf.d/10-boot.conf
	echo "uefi_stub=/lib/systemd/boot/efi/linuxx64.efi.stub" >> /etc/dracut.conf.d/10-boot.conf
	if [[ $fs_type != "btrfs"  ]]; then
echo 'kernel_cmdline="quiet lsm=capability,landlock,yama,bpf,apparmor rd.luks.name='$luks_root_uuid'=cryptroot rd.lvm.vg='$hostname' root=/dev/'$hostname'/root rd.luks.allow-discards"' >> /etc/dracut.conf.d/10-boot.conf
	fi
fi
#echo 'early_microcode="yes"' >> /mnt/etc/dracut.conf.d/10-boot.conf


# harden sysctl 

mkdir /etc/sysctl.d
touch /etc/sysctl.d/10-void-user.conf

echo -e "dev.tty.ldisc_autoload=0
fs.protected_symlinks=1
fs.protected_hardlinks=1
fs.protected_fifos=2
fs.protected_regular=2
fs.suid_dumpable=0
kernel.core_pattern=|/bin/false
kernel.dmesg_restrict=1
kernel.kexec_load_disabled=1
kernel.yama.ptrace_scope=2
kernel.kptr_restrict=2
kernel.printk=3 3 3 3
kernel.unprivileged_bpf_disabled=1
kernel.sysrq=4
kernel.unprivileged_userns_clone=0
kernel.perf_event_paranoid=3
kernel.randomize_va_space=2
kernel.msgmnb=65535
kernel.msgmax=65535
net.core.bpf_jit_harden=2
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
vm.unprivileged_userfaultfd=0" > /etc/sysctl.d/99-void-user.conf

#secure boot
if [[ $secure_boot == 0 ]]; then

	sbctl create-keys
	sbctl enroll-keys
	echo 'uefi_secureboot_cert="/var/lib/sbctl/keys/db/db.pem"' >> /etc/dracut.conf.d/10-boot.conf
	echo 'uefi_secureboot_key="/var/lib/sbctl/keys/db/db.key"' >> /etc/dracut.conf.d/10-boot.conf
fi

if [[ $bm != "grub" ]]; then
	echo "CREATE_UEFI_BUNDLES=yes" >> /etc/default/dracut-uefi-hook
	echo 'UEFI_BUNDLE_DIR="efi/EFI/Linux/"' >> /etc/default/dracut-uefi-hook
	mkdir -p /efi/EFI/Linux
fi

xbps-install -SuyR $void_repo -r xbps
xbps-install -SyR $void_repo -r void-repo-nonfree

if [[ $graphical == "kde" ]]; then
	xbps-install -SyR $void_repo -r $apps $apps_kde $apps_intel $apps_optional $fonts

elif [[ $graphical == "gnome" ]]; then
	xbps-install -SyR $void_repo -r $apps $apps_gnome $apps_intel $apps_optional $fonts

elif [[ $graphical == "xfce" ]]; then
	xbps-install -SyR $void_repo -r $apps $apps_xfce $apps_intel $apps_optional $fonts

else
	xbps-install -SyR $void_repo -r $apps_minimal $fonts

	#iwd
	mkdir -p /etc/iwd
	touch /etc/iwd/main.conf

	echo -e "[General]
	EnableNetworkConfiguration=true
	[Network]
	RoutePriorityOffset=200
	NameResolvingService=none
	EnableIPv6=false" >> /etc/iwd/main.conf

fi

#firewall
touch /etc/nftables.conf

echo -e 'flush ruleset

table inet filter {
	chain input {
		type filter hook input priority 0; policy drop;
		ct state invalid counter drop comment "early drop of invalid packets"
		ct state {established, related} counter accept comment "accept all connections related to connections made by us"
		iif lo accept comment "accept loopback"
		iif != lo ip daddr 127.0.0.1/8 counter drop comment "drop connections to loopback not coming from loopback"
		iif != lo ip6 daddr ::1/128 counter drop comment "drop connections to loopback not coming from loopback"
		ip protocol icmp counter accept comment "accept all ICMP types"
		meta l4proto ipv6-icmp counter accept comment "accept all ICMP types"
		udp dport mdns ip daddr 224.0.0.251 counter accept comment "IPv4 mDNS"
		udp dport mdns ip6 daddr ff02::fb counter accept comment "IPv6 mDNS"
		#tcp dport 22 counter accept comment "accept SSH"
		counter comment "count dropped packets"
	}
	chain forward {
		type filter hook forward priority 0; policy drop;
		counter comment "count dropped packets"
	}
	# If were not counting packets, this chain can be omitted.
	chain output {
		type filter hook output priority 0; policy accept;
		counter comment "count accepted packets"
	}
}' > /etc/nftables.conf


if [[ $graphical != "" ]]; then

	#pipewire
	mkdir -p /etc/pipewire/pipewire.conf.d
	ln -s /usr/share/examples/wireplumber/10-wireplumber.conf /etc/pipewire/pipewire.conf.d/
	ln -s /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/

	#start pipewire.desktop for kde gnome etc
	ln -s /usr/share/applications/pipewire.desktop /etc/xdg/autostart/pipewire.desktop

	#octoxbps-notifier
	ln -s /usr/share/applications/octoxbps-notifier.desktop /etc/xdg/autostart/octoxbps-notifier.desktop

for serv1 in ${rm_services[@]}; do

	unlink /var/service/$serv1
done

for serv2 in ${en_services[@]}; do

	ln -s /etc/sv/$serv2 /var/service
	
done
fi

if [[ $bm != "grub" ]]; then
	touch /etc/kernel.d/post-install/10-uefi-boot
	echo "#!/bin/sh" > /etc/kernel.d/post-install/10-uefi-boot
	echo "mv /efi/EFI/Linux/linux-* /efi/EFI/Linux/linuxOLD.efi" >> /etc/kernel.d/post-install/10-uefi-boot
	chmod +x /etc/kernel.d/post-install/10-uefi-boot

	touch /etc/kernel.d/post-install/99-uefi-boot
	echo "#!/bin/sh" > /etc/kernel.d/post-install/99-uefi-boot
	echo "cp /efi/EFI/Linux/linux-* /efi/EFI/Linux/linux.efi" >> /etc/kernel.d/post-install/99-uefi-boot
	chmod +x /etc/kernel.d/post-install/99-uefi-boot
fi

#rc.conf
echo 'KEYMAP="uk"' >> /etc/rc.conf
echo 'FONT="ter-v24n"' >> /etc/rc.conf

#apparmor
sed -i 's/^#*APPARMOR=.*$/APPARMOR=enforce/i' /etc/default/apparmor
sed -i 's/^#*write-cache/write-cache/i' /etc/apparmor/parser.conf

touch /home/$username/.bash_aliases
chown $username:$username /home/$username/.bash_aliases

echo -e "source /home/$username/.bash_aliases
fastfetch
complete -cf xi xs" >> /home/$username/.bashrc
echo 'eval "$(starship init bash)"' >> /home/$username/.bashrc #need file in $home/.config/starship.toml

mkdir -p /home/$username/.config
touch /home/$username/.config/starship.toml
chown -R $username:$username /home/$username/.config

 echo -e "add_newline = true
 [character] # The name of the module we are configuring is 'character'
 success_symbol = '[➜](bold green)' # The 'success_symbol' segment is being set to '➜' with the color 'bold green'
 [package]
 disabled = true" > /home/$username/.config/starship.toml

echo -e "alias xi='doas xbps-install -S' 
alias xu='doas xbps-install -Suy'
alias xs='xbps-query -Rs'
alias xr='doas xbps-remove -oOR'
alias xq='xbps-query'
alias xsi='xbps-query -m'
alias sudo='doas'
alias dmesg='doas dmesg | less'
alias logs='doas svlogtail | less'
alias e='nano'
alias de='doas nano'
alias vsv='doas vsv'
alias reboot='doas reboot'
alias poweroff='doas poweroff'
alias ss='ss -atup'
alias cat='bat'
alias gitssh='ssh -T git@github.com'
alias ls='ls -all'
alias sensors='watch sensors'" >> /home/$username/.bash_aliases

#fonts
ln -s /usr/share/fontconfig/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d/
#xbps-reconfigure -fr fontconfig /mnt/

#doas
echo "permit persist setenv {PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin} :wheel" > /etc/doas.conf
chown -c root:root /etc/doas.conf
chmod -c 0400 /etc/doas.conf

#ssh / cron hardening permissions

echo -e "PasswordAuthentication no
PermitRootLogin no" >> /etc/ssh/sshd_config

chown -c root:root /etc/ssh/sshd_config
chmod -c 0400 /etc/ssh/sshd_config
chown -c root:root /etc/cron.daily
chmod -c 0400 /etc/cron.daily

#blacklist modules and drivers not needed
touch /etc/modprobe.d/blacklist.conf
echo -e "blacklist dccp
install dccp /bin/false
blacklist sctp
install sctp /bin/false
blacklist rds
install rds /bin/false
blacklist tipc
install tipc /bin/false
blacklist firewire-core
install firewire-core /bin/false
blacklist thunderbolt
install thunderbolt /bin/false" > /etc/modprobe.d/blacklist.conf

#time zone
ln -sf /usr/share/zoneinfo/Europe/Lisbon /etc/localtime

#ignore packages
touch /etc/xbps.d/99-ignorepkgs.conf

ignore_pkgs=("sudo" "linux-firmware-amd" "linux-firmware-nvidia" "linux-firmware-broadcom" "ipw2100-firmware" "ipw2200-firmware")

for pkg in ${ignore_pkgs[@]}; do
   echo "ignorepkg="$pkg >> /etc/xbps.d/99-ignorepkgs.conf
   xbps-remove -oOR $pkg -y
done

# enable flatpak

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

#dns
#for dns in ${dns_list[@]}; do

  #echo "nameserver="$dns >> /mnt/etc/resolv.conf
  
if [[ $bm != "grub" ]]; then
	efibootmgr -c -d $disk -p 1 -L "Void Linux OLD" -l "\EFI\Linux\linuxOLD.efi"
	efibootmgr -c -d $disk -p 1 -L "Void Linux" -l "\EFI\Linux\linux.efi"
elif [[ $bm == "refind" ]]; then
    refind-install
	if [[ $secure_boot == 0 ]]; then
		 sbctl sign -s /efi/EFI/refind/refind_x64.efi
	fi
else
	if [[ $fs_type != "btrfs" ]]; then
	echo 'GRUB_CMDLINE_LINUX="rd.luks.uuid='$luks_uuid' rd.lvm.vg='$hostname' lsm=capability,landlock,yama,bpf,apparmor"' >> /etc/default/grub
	else
	echo 'GRUB_CMDLINE_LINUX="root=UUID='$ROOT_UUID' lsm=capability,landlock,yama,bpf,apparmor"' >> /etc/default/grub
	echo "--timeshift-auto" > /etc/sv/grub-btrfs/conf
	echo 'GRUB_BTRFS_ENABLE_CRYPTODISK="true"' >> /etc/default/grub-btrfs/config
	fi
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
dd bs=1 count=64 if=/dev/urandom of=/boot/volume.key
echo $luks_pw | cryptsetup luksAddKey $disk'2' /boot/volume.key
chmod 000 /boot/volume.key
chmod -R g-rwx,o-rwx /boot
echo "cryptroot UUID=$luks_uuid /boot/volume.key luks" >> /etc/crypttab
echo 'install_items+=" /boot/volume.key /etc/crypttab "' >> /etc/dracut.conf.d/10-boot.conf

grub-install --target=x86_64-efi --efi-directory=/efi  --boot-directory=/boot --bootloader-id="Void" --disable-shim-lock --modules="tpm"

grub-mkconfig -o /boot/grub/grub.cfg
	if [[ $secure_boot == 0 ]]; then
		sbctl sign -s /efi/EFI/Void/grubx64.efi
		kern_ver=$(uname -r)
		sbctl sign -s /boot/vmlinuz-$kern_ver
	fi
fi

xbps-reconfigure -far

EOF

echo -e "\nUnmount Void installation and reboot?(y/n)\n"
read tmp
if [[ $tmp == "y" ]]; then
	umount -R /mnt
 	reboot 
  shutdown -r now
fi

echo -e "\nFinish\n"
