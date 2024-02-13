#!/bin/bash
#read this script carefully before use it!!
#this only works with uefi and intel graphics
#you must change the variables to your taste


username="k2"

luks_pw="123" #password for disk encryption

root_pw="123" #root password

user_pw="123" #user password

efi_part_size="300M"

root_part_size="" # if it is empty it will create only a root partition. (and doesnt create a home partition with the remaining space)

hostname="xpto"

fs_type="xfs" #only support ext4 or xfs


disk="/dev/sda" #or /dev/vda for virt-manager

luks_root_uuid=$(blkid -o value -s UUID  /dev/mapper/$hostname-root)
luks_home_uuid=$(blkid -o value -s UUID  /dev/mapper/$hostname-home)
boot_uuid=$(blkid -o value -s UUID  $disk'1')

cr="chroot /mnt/gentoo"

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

	pvcreate --name root -l 100%FREE $hostname
else
	pvcreate --name root -L $root_part_size $hostname
	pvcreate --name home -l 100%FREE $hostname
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

gpg --import /usr/share/openpgp-keys/gentoo-release.asc
wget https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-20240204T134829Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

sed COMMON_FLAGS="-O2 -pipe"
sed -i 's@"-02 -pipe"@"-march=native -O2 -pipe"@g' /mnt/gentoo/etc/portage/make.conf
#arch-chroot /mnt/gentoo
echo "MAKEOPTS="-j4 -l4" >> /mnt/gentoo/etc/portage/make.conf

#INSTALL BASE SYSTEM
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run 




$cr mkdir --parents /etc/portage/repos.conf
$cr cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf

 $cr echo 'GENTOO_MIRRORS="https://mirrors.ptisp.pt/gentoo/"' >> /etc/portage/make.conf

$cr echo '[binhost]' > /etc/portage/binrepos.conf/gentoo.conf
$cr echo 'priority = 9999' >> /etc/portage/binrepos.conf/gentoo.conf
$cr echo 'sync-uri = https://mirrors.ptisp.pt/gentoo/releases/amd64/binpackages/17.1/x86-64/' >> /etc/portage/binrepos.conf/gentoo.conf

$cr echo 'FEATURES="${FEATURES} getbinpkg"' >> /etc/portage/make.conf
$cr echo 'FEATURES="${FEATURES} binpkg-request-signature"' >> /etc/portage/make.conf

$cr echo 'ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"' >> /etc/portage/make.conf

$cr echo "Europe/Lisbon" > /etc/timezone
$cr emerge --config sys-libs/timezone-data
$cr echo "en_US ISO-8859-1" >> /etc/locale.gen
$cr echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
$cr locale-gen

#KERNEL CONFIG

$cr emerge sys-kernel/linux-firmware
$cr emerge sys-firmware/intel-microcode
$cr echo "sys-kernel/installkernel dracut uki" >> /etc/portage/package.use/installkernel
$cr emerge sys-kernel/gentoo-kernel-bin
$cr echo 'uefi="yes"' >>  /etc/dracut.conf
$cr echo 'kernel_cmdline="rd.luks.name='$luks_root_uuid'=cryptroot root=/dev/'$hostname'/root"' >> /etc/dracut.conf

#CONFIG SYSTEM

$cr echo -e "UUID=$luks_root_uuid	/	$fs_type	defaults,noatime	0	1" >> /etc/fstab
if [[ ! -z $root_part_size ]]; then

	$cr echo -e "UUID=$luks_home_uuid	/home	$fs_type	defaults,noatime	0	2" >> /etc/fstab
fi

	$cr echo -e "UUID=$boot_uuid	  /efi	    vfat	umask=0077	0	2" >> /etc/fstab

$cr echo $hostname > /etc/hostname

$cr echo "$root_pw\n$root_pw" | passwd -q root

$cr emerge sys-fs/xfsprogs

#CONFIG BOOTLOADER

$cr emerge sys-boot/efibootmgr

$cr mkdir -p /efi/efi/gentoo
$cr cp /boot/vmlinuz-* /efi/efi/gentoo/bzImage.efi 
$cr efibootmgr --create --disk /dev/$disk --part 1 --label "gentoo_uefi" --loader "\efi\gentoo\bzImage.efi"



echo -e "\nUnmount gentoo installation and reboot?(y/n)\n"
read tmp
if [[ $tmp == "y" ]]; then
	exit
        
	 	umount -l /mnt/gentoo/dev{/shm,/pts,}
 	umount -R /mnt/gentoo
 	reboot 
  #shutdown -r now
fi

echo -e "\nFinish\n"
