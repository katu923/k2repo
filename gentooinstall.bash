#!/bin/bash
#read this script carefully before use it!!
#this only works with uefi and intel graphics
#you must change the variables to your taste


username="k2"

luks_pw="123" #password for disk encryption

root_pw="123" #root password

#user_pw="123" #user password

efi_part_size="512M"

root_part_size="18G" # if it is empty it will create only a root partition. (and doesnt create a home partition with the remaining space)

hostname="xpto"

fs_type="ext4"

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
wget https://gentoo.osuosl.org/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-20240218T170410Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

#INSTALL BASE SYSTEM

#arch-chroot /mnt/gentoo
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run 

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
chroot /mnt/gentoo/ emerge-webrsync
#sed -i 's@"-02 -pipe"@"-march=native -O2 -pipe"@g' /mnt/gentoo/etc/portage/make.conf
#chroot /mnt/gentoo/ echo 'MAKEOPTS="-j4 -l4"' >> /etc/portage/make.conf

 echo 'FEATURES="${FEATURES} getbinpkg"' >> /mnt/gentoo/etc/portage/make.conf
 echo 'FEATURES="${FEATURES} binpkg-request-signature"' >> /mnt/gentoo/etc/portage/make.conf

 echo 'ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"' >> /mnt/gentoo/etc/portage/make.conf
echo 'VIDEO_CARDS="qxl"' >> /mnt/gentoo/etc/portage/make.conf

#openrc
echo "Europe/Lisbon" > /mnt/gentoo/etc/timezone
chroot /mnt/gentoo/ emerge --config sys-libs/timezone-data
#systemd
#ln -sf ../usr/share/zoneinfo/Europe/Brussels /mnt/gentoo/etc/localtime

 echo "en_US ISO-8859-1" >> /mnt/gentoo/etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /mnt/gentoo/etc/locale.gen
 chroot /mnt/gentoo/ locale-gen

 
 #KERNEL CONFIG

 chroot /mnt/gentoo emerge -avgq sys-kernel/linux-firmware sys-firmware/intel-microcode
  #openrc
 echo "sys-kernel/installkernel dracut uki" > /mnt/gentoo/etc/portage/package.use/installkernel
 echo "sys-fs/lvm2 lvm" > /mnt/gentoo/etc/portage/package.use/lvm2
 echo "sys-apps/systemd-utils boot kernel-install" > /mnt/gentoo/etc/portage/package.use/systemd-utils
 
home_uuid=$(blkid -o value -s UUID /dev/mapper/$hostname-home)
root_uuid=$(blkid -o value -s UUID /dev/mapper/$hostname-root)
luks_uuid=$(blkid -o value -s UUID $disk'2')
boot_uuid=$(blkid -o value -s UUID $disk'1')

chroot /mnt/gentoo echo -e "UUID=$root_uuid	/	$fs_type	defaults,noatime	0	1" >> /mnt/gentoo/etc/fstab
if [[ ! -z $root_part_size ]]; then

chroot /mnt/gentoo echo -e "UUID=$home_uuid	/home	$fs_type	defaults,noatime	0	2" >> /mnt/gentoo/etc/fstab
fi

chroot /mnt/gentoo echo -e "UUID=$boot_uuid	/efi 	    vfat	umask=0077	0	2" >> /mnt/gentoo/etc/fstab

 
 mkdir -p /mnt/gentoo/etc/dracut.conf.d
 touch /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 echo 'add_dracutmodules+=" lvm crypt dm "' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 echo 'uefi="yes"' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 echo 'kernel_cmdline="rd.luks.uuid='$luks_uuid' root=UUID='$root_uuid'"' >> /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 mkdir -p /mnt/gentoo/efi/EFI/Linux

#CONFIG SYSTEM
 
echo $hostname > /mnt/gentoo/etc/hostname

#openrc
chroot /mnt/gentoo/ emerge -avgq lvm2 systemd-utils cryptsetup efibootmgr

#mkdir -p /etc/iwd

#chroot /mnt/gentoo touch /etc/iwd/main.conf
#chroot /mnt/gentoo echo "[General]" > /etc/iwd/main.conf
#chroot /mnt/gentoo echo "EnableNetworkConfiguration=true" >> /etc/iwd/main.conf
#chroot /mnt/gentoo echo "[Network]" >> /etc/iwd/main.conf
#echo "RoutePriorityOffset=200" >> /etc/iwd/main.conf
#chroot /mnt/gentoo echo "NameResolvingService=none" >> /etc/iwd/main.conf
#echo "EnableIPv6=false" >> /etc/iwd/main.conf

#echo "target=home" >> /etc/conf.d/dmcrypt
#echo 'source="/dev/vda3"' >> /etc/conf.d/dmcrypt

#chroot /mnt/gentoo/ emerge -aunDN @world
chroot /mnt/gentoo/ emerge -avgq sys-kernel/gentoo-kernel-bin
#CONFIG BOOTLOADER

 cp /mnt/gentoo/efi/EFI/Linux/*dist.efi /mnt/gentoo/efi/EFI/Linux/linux.efi
 
 chroot /mnt/gentoo efibootmgr -c -d $disk -p 1 -L "Gentoo" -l "\EFI\Linux\linux.efi"


chroot /mnt/gentoo/ rc-update add dmcrypt boot
chroot /mnt/gentoo/ rc-update add lvm boot
#relabeling -selinux
#chroot /mnt/gentoo rlpkg -a -r

#fim

chroot /mnt/gentoo useradd -m -G users,wheel,audio,video -s /bin/bash $username

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
