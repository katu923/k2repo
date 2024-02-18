#!/bin/bash
#read this script carefully before use it!!
#this only works with uefi and intel graphics
#you must change the variables to your taste


username="k2"

luks_pw="123" #password for disk encryption

root_pw="123" #root password

user_pw="123" #user password

efi_part_size="512M"

root_part_size="" # if it is empty it will create only a root partition. (and doesnt create a home partition with the remaining space)

hostname="xpto"

disk="/dev/vda" #or /dev/vda for virt-manager


#PREPARE DISKS

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


mount /dev/$hostname/root /mnt/gentoo

if [[ ! -z $root_part_size ]]; then
	mkdir -p /mnt/gentoo/home
	mount /dev/$hostname/home /mnt/gentoo/home
fi

	mkfs.vfat $efi_part
	mkdir -p /mnt/gentoo/efi
	mount $efi_part /mnt/gentoo/efi
 

 
#STAGE FILE

cd /mnt/gentoo

wget https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-20240204T134829Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

#INSTALL BASE SYSTEM



arch-chroot /mnt/gentoo
exit

chroot /mnt/gentoo/ echo "nameserver 1.1.1.2" > /etc/resolv.conf
chroot /mnt/gentoo/ echo "nameserver 1.0.0.2" >> /etc/resolv.conf
chroot /mnt/gentoo/ mkdir --parents /etc/portage/repos.conf
chroot /mnt/gentoo/ cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
chroot /mnt/gentoo/ emerge-webrsync
chroot /mnt/gentoo/ sed -i 's@"-02 -pipe"@"-march=native -O2 -pipe"@g' /etc/portage/make.conf
chroot /mnt/gentoo/ echo "MAKEOPTS="-j4 -l4" >> /etc/portage/make.conf
chroot /mnt/gentoo/ echo 'GENTOO_MIRRORS="https://mirrors.ptisp.pt/gentoo/"' >> /etc/portage/make.conf

 chroot /mnt/gentoo/ echo '[binhost]' > /etc/portage/binrepos.conf/gentoo.conf
 chroot /mnt/gentoo/ echo 'priority = 9999' >> /etc/portage/binrepos.conf/gentoo.conf
 chroot /mnt/gentoo/ echo 'sync-uri = https://mirrors.ptisp.pt/gentoo/releases/amd64/binpackages/17.1/x86-64/' >> /etc/portage/binrepos.conf/gentoo.conf

 chroot /mnt/gentoo/ echo 'FEATURES="${FEATURES} getbinpkg"' >> /etc/portage/make.conf
 chroot /mnt/gentoo/ echo 'FEATURES="${FEATURES} binpkg-request-signature"' >> /etc/portage/make.conf

 chroot /mnt/gentoo/ echo 'ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"' >> /etc/portage/make.conf

 chroot /mnt/gentoo/ echo "Europe/Lisbon" > /etc/timezone
 chroot /mnt/gentoo/ emerge --config sys-libs/timezone-data
 chroot /mnt/gentoo/ echo "en_US ISO-8859-1" >> /etc/locale.gen
 chroot /mnt/gentoo/ echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
 chroot /mnt/gentoo/ locale-gen
 
 #KERNEL CONFIG

 chroot /mnt/gentoo/ emerge sys-kernel/linux-firmware
 #emerge sys-firmware/intel-microcode
 chroot /mnt/gentoo/ echo "sys-kernel/installkernel dracut uki" > /etc/portage/package.use/installkernel
 chroot /mnt/gentoo/ echo "sys-fs/lvm2 lvm" > /etc/portage/package.use/lvm2
 chroot /mnt/gentoo/ echo "sys-apps/systemd-utils boot kernel-install" > /etc/portage/package.use/systemd-utils
 
 
 chroot /mnt/gentoo/ mkdir -p /etc/dracut.conf.d
 chroot /mnt/gentoo/ touch /etc/dracut.conf.d/10-dracut.conf
 chroot /mnt/gentoo/ echo 'adddracutmodules=" lvm crypt dm"' >>  /etc/dracut.conf.d/10-dracut.conf
 chroot /mnt/gentoo/ echo 'uefi="yes"' >>  /etc/dracut.conf.d/10-dracut.conf
 
 chroot /mnt/gentoo/ echo 'kernel_cmdline="rd.luks.uuid= root=UUID="  >> /etc/dracut.conf.d/10-dracut.conf

chroot /mnt/gentoo/ mkdir -p /efi/EFI/Linux

#CONFIG SYSTEM

 echo -e "/dev/vda2	/	xfs	defaults,noatime	0	1" >> /etc/fstab
 echo -e "/dev/mapper/home	/home	ext4	defaults,noatime	0	2" >> /etc/fstab
 echo -e "/dev/vda1  /efi	    vfat	umask=0077	0	2" >> /etc/fstab

chroot /mnt/gentoo/ echo $hostname > /etc/hostname

 chroot /mnt/gentoo/ echo "$root_pw\n$root_pw" | passwd -q root

 #emerge sys-fs/xfsprogs
chroot /mnt/gentoo/ emerge cryptsetup
chroot /mnt/gentoo/ emerge systemd-utils
#emerge iwd
#mkdir -p /etc/iwd

#touch /etc/iwd/main.conf
#echo "[General]" > /etc/iwd/main.conf
#echo "EnableNetworkConfiguration=true" >> /etc/iwd/main.conf
#echo "[Network]" >> /etc/iwd/main.conf
#echo "RoutePriorityOffset=200" >> /etc/iwd/main.conf
#echo "NameResolvingService=none" >> /etc/iwd/main.conf
#echo "EnableIPv6=false" >> /etc/iwd/main.conf

#echo "target=home" >> /etc/conf.d/dmcrypt
#echo 'source="/dev/vda3"' >> /etc/conf.d/dmcrypt
chroot /mnt/gentoo/ emerge -aunDN @world
chroot /mnt/gentoo/ emerge sys-kernel/gentoo-kernel-bin
#CONFIG BOOTLOADER

 chroot /mnt/gentoo/ emerge sys-boot/efibootmgr

chroot /mnt/gentoo/ cp /efi/EFI/Linux/*-dist.efi linux.efi
 
 chroot /mnt/gentoo/ efibootmgr -c --disk /dev/vda --part 1 -l "\EFI\Linux\linux.efi"


rc-update add dmcrypt boot
rc-update add lvm boot


EOF
#fim

echo -e "\nUnmount gentoo installation and reboot?(y/n)\n"
read tmp
if [[ $tmp == "y" ]]; then
	exit
        
	 	umount -l /mnt/gentoo/dev{/shm,/pts,}
 	umount -R /mnt/gentoo
# 	reboot 
  #shutdown -r now
fi

echo -e "\nFinish\n"
