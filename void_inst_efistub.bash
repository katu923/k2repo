#!/bin/bash

#this script only works with uefi
#you must change the variables to your taste


username="k2"

luks_pw="123" #password for disk encryption

root_pw="123" #root password

user_pw="123" #user password

user_groups="wheel,kvm"

efi_part_size="512M"

root_part_size="25G" # if it is empty "" it will create only a root partition. (and doesnt create a home partition with the remaining space)

hostname="xpto"

fs_type="ext4"

libc="" #empty is glibc other value is musl

language="en_US.UTF-8"

graphical="kde" #empty "" it will install only base system and apps_minimal

disk="/dev/sda" #or /dev/vda for virt-manager

secure_boot="yes" # better leave this empty "" you can break your bios

void_repo="https://repo-fastly.voidlinux.org"
#after install change mirror with xmirror

ARCH="x86_64"


apps="xorg-minimal dejavu-fonts-ttf nano elogind dbus socklog-void apparmor chrony mpv"\
" xdg-desktop-portal xdg-user-dirs xdg-desktop-portal-gtk xdg-utils octoxbps xmirror"\
" neofetch git unzip unrar flatpak pipewire wireplumber fish-shell firefox"\
" font-adobe-source-code-pro ufw gufw vsv btop opendoas net-tools zramen"
 

apps_intel="mesa-dri mesa-vulkan-intel intel-video-accel vulkan-loader intel-ucode"

apps_kde="kde5 kde5-baseapps kcron ark user-manager print-manager spectacle kdeconnect okular"\
" plasma-wayland-protocols xdg-desktop-portal-kde plasma-firewall plasma-applet-active-window-control skanlite gwenview"\
" kwalletmanager kolourpaint sddm-kcm partitionmanager kcalc plasma-disks flatpak-kcm kio-gdrive"

#for test
apps_minimal="nano apparmor neofetch ufw vsv opendoas fish-shell zramen"

rm_services=("agetty-tty3" "agetty-tty4" "agetty-tty5" "agetty-tty6")
en_services=("dbus" "chronyd" "udevd" "uuidd" "cupsd" "socklog-unix" "nanoklogd" "zramen" "ufw" "NetworkManager" "sddm")


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
echo $luks_pw | cryptsetup -q --cipher aes-xts-plain64 --key-size 256 --hash sha256 --iter-time 5000 --use-random --type luks2 luksFormat $luks_part
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
	mkdir -p /mnt/boot
	mount $efi_part /mnt/boot


mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/

 	echo y | XBPS_ARCH=$ARCH xbps-install -SyR $void_repo/current/$libc -r /mnt base-system cryptsetup lvm2 efibootmgr dracut-uefi gummiboot-efistub sbctl

#luks_uuid=$(blkid -o value -s UUID $luks_part)

chroot /mnt chown root:root /
chroot /mnt chmod 755 /

chroot /mnt useradd $username
chroot /mnt usermod -aG $user_groups $username

cat << EOF | chroot /mnt
echo "$root_pw\n$root_pw" | passwd -q root
echo "$user_pw\n$user_pw" | passwd -q $username
EOF

#Set hostname and language/locale
echo $hostname > /mnt/etc/hostname


if [[ -z $libc ]]; then
    echo "LANG=$language" > /mnt/etc/locale.conf
    echo "en_US.UTF-8 UTF-8" >> /mnt/etc/default/libc-locales
    xbps-reconfigure -fr /mnt/ glibc-locales
fi

luks_root_uuid=$(blkid -o value -s UUID  /mnt/dev/mapper/$hostname-root)
luks_home_uuid=$(blkid -o value -s UUID  /mnt/dev/mapper/$hostname-home)
boot_uuid=$(blkid -o value -s UUID  /mnt$disk'1')

echo -e "UUID=$luks_root_uuid	/	$fs_type	defaults,noatime	0	1" >> /mnt/etc/fstab
if [[ ! -z $root_part_size ]]; then

	echo -e "UUID=$luks_home_uuid	/home	$fs_type	defaults,noatime	0	2" >> /mnt/etc/fstab
fi

	echo -e "UUID=$boot_uuid	  /boot	    vfat	defaults	0	2" >> /mnt/etc/fstab


#add hostonly to dracut
echo "hostonly=yes" >> /mnt/etc/dracut.conf.d/10-boot.conf
echo 'uefi="yes"' >>  /mnt/etc/dracut.conf.d/10-boot.conf
echo "uefi_stub=/usr/lib/gummiboot/linuxx64.efi.stub" >>/mnt/etc/dracut.conf.d/10-boot.conf

# change sysctl
echo "fs.protected_regular=2" >> /mnt/usr/lib/sysctl.d/10-void.conf
echo "fs.protected_fifos=2" >> /mnt/usr/lib/sysctl.d/10-void.conf
echo "net.ipv4.conf.all.rp_filter=1" >> /mnt/etc/sysctl.conf

if [[ ! -z $secure_boot ]]; then

chroot /mnt sbctl create-keys
chroot /mnt sbctl enroll-keys -m -i #this use microsoft keys to uefi secure boot
fi


# Options for the kernel hook script installed by the efibootmgr package.
echo "MODIFY_EFI_ENTRIES=1" > /mnt/etc/default/efibootmgr-kernel-hook
# To allow efibootmgr to modify boot entries, set
# MODIFY_EFI_ENTRIES=1
# Kernel command-line options.  Example:
echo 'OPTIONS="loglevel=4 apparmor=1 security=apparmor rd.luks.name='$luks_root_uuid'=cryptroot rd.lvm.vg='$hostname 'root=/dev/'$hostname'/root"' >> /mnt/etc/default/efibootmgr-kernel-hook
# Disk where EFI Partition is.  Default is /dev/sda

echo 'DISK="'$disk'"' >> /mnt/etc/default/efibootmgr-kernel-hook
# Partition number of EFI Partition.  Default is 1
echo "PART=1" >> /mnt/etc/default/efibootmgr-kernel-hook


echo 'efibootmgr -qc $args -L "Void Linux with kernel ${major_version}" -l /efi/EFi/void/linux-${VERSION}.efi -u "${OPTIONS}"' >> /mnt/etc/kernel.d/post-install/50-efibootmgr

echo 'sbctl sign -s /boot/efi/EFI/void/linux-${VERSION}.efi' >> /mnt/etc/kernel.d/post-install/50-efibootmgr


echo "CREATE_UEFI_BUNDLES=yes" >> /mnt/etc/default/dracut-uefi-hook
echo 'KERNEL_CMDLINE="loglevel=4 apparmor=1 security=apparmor rd.luks.name='$luks_root_uuid'=cryptroot rd.lvm.vg='$hostname 'root=/dev/'$hostname'/root"' >> /mnt/etc/default/dracut-uefi-hook

xbps-reconfigure -far /mnt/

sed -i "s/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/" /mnt/etc/sudoers

xbps-install -SuyR $void_repo/current/$libc -r /mnt xbps
xbps-install -SyR $void_repo/current/$libc -r /mnt/ void-repo-nonfree
if [[ $graphical == "kde" ]]; then
xbps-install -SyR $void_repo/current/$libc -r /mnt $apps $apps_kde $apps_intel

#pipewire
chroot /mnt ln -s /usr/share/applications/pipewire.desktop /etc/xdg/autostart/pipewire.desktop
chroot /mnt ln -s /usr/share/applications/wireplumber.desktop /etc/xdg/autostart/wireplumber.desktop
chroot /mnt ln -s /usr/share/applications/pipewire-pulse.desktop /etc/xdg/autostart/pipewire-pulse.desktop

#octoxbps-notifier
chroot /mnt ln -s /usr/share/applications/octoxbps-notifier.desktop /etc/xdg/autostart/octoxbps-notifier.desktop
else
xbps-install -SyR $void_repo/current/$libc -r /mnt $apps_minimal
fi


for serv in ${rm_services[@]}; do

	chroot /mnt unlink /var/service/$serv
done

for serv in ${en_services[@]}; do

	chroot /mnt ln -s /etc/sv/$serv /var/service
	
done

#apparmor
sed -i 's/^#*APPARMOR=.*$/APPARMOR=enforce/i' /mnt/etc/default/apparmor
sed -i 's/^#*write-cache/write-cache/i' /mnt/etc/apparmor/parser.conf


chroot /mnt touch /home/$username/.bash_aliases
chroot /mnt chown $username:$username /home/$username/.bash_aliases

echo "source /home/$username/.bash_aliases" >> /mnt/home/$username/.bashrc
echo "neofetch" >> /mnt/home/$username/.bashrc

echo "alias xi='sudo xbps-install -S'" >> /mnt/home/$username/.bash_aliases 
echo "alias xu='sudo xbps-install -Suy'" >> /mnt/home/$username/.bash_aliases
echo "alias xs='xbps-query -Rs'" >> /mnt/home/$username/.bash_aliases
echo "alias xr='sudo xbps-remove -oOR'" >> /mnt/home/$username/.bash_aliases
echo "alias xq='xbps-query'" >> /mnt/home/$username/.bash_aliases
echo "alias xsi='xbps-query -m'" >> /mnt/home/$username/.bash_aliases
echo "alias sudo='doas'" >> /mnt/home/$username/.bash_aliases
echo "alias dmesg='sudo dmesg'" >> /mnt/home/$username/.bash_aliases



#doas
echo "permit persist :wheel" > /mnt/etc/doas.conf

#chroot /mnt touch /etc/iwd/main.conf
#echo "[General]" > /mnt/etc/iwd/main.conf
##echo "EnableNetworkConfiguration=true" >> /mnt/etc/iwd/main.conf
#echo "[Network]" >> /mnt/etc/iwd/main.conf
#echo "RoutePriorityOffset=200" >> /mnt/etc/iwd/main.conf
#echo "NameResolvingService=none" >> /mnt/etc/iwd/main.conf
#echo "EnableIPv6=false" >> /mnt/etc/iwd/main.conf


echo -e "\nUnmount Void installation and reboot?(y/n)\n"
read tmp
if [[ $tmp == "y" ]]; then
	umount -R /mnt				
	shutdown -r now
fi

echo -e "\nFinish\n"
