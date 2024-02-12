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

	vgcreate --name root -l 100%FREE $hostname
else
	vgcreate --name root -L $root_part_size $hostname
	vgcreate --name home -l 100%FREE $hostname
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

cd /mnt/gentoo

gpg --import /usr/share/openpgp-keys/gentoo-release.asc
wget https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-20240204T134829Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

arch-chroot /mnt/gentoo
source /etc/profile
export PS1="(chroot) ${PS1}"


luks_root_uuid=$(blkid -o value -s UUID  /dev/mapper/$hostname-root)
luks_home_uuid=$(blkid -o value -s UUID  /dev/mapper/$hostname-home)
boot_uuid=$(blkid -o value -s UUID  $disk'1')


mkdir --parents /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf

 echo 'GENTOO_MIRRORS="https://mirrors.ptisp.pt/gentoo/"' >> /etc/portage/make.conf

echo '[binhost]' > /etc/portage/binrepos.conf/gentoo.conf
echo 'priority = 9999' >> /etc/portage/binrepos.conf/gentoo.conf
echo 'sync-uri = https://mirrors.ptisp.pt/gentoo/releases/amd64/binpackages/17.1/x86-64/' >> /etc/portage/binrepos.conf/gentoo.conf

echo 'FEATURES="${FEATURES} getbinpkg"' >> /etc/portage/make.conf
echo 'FEATURES="${FEATURES} binpkg-request-signature"' >> /etc/portage/make.conf

echo 'ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"' >> /etc/portage/make.conf

echo "Europe/Lisbon" > /etc/timezone
emerge --config sys-libs/timezone-data
echo "en_US ISO-8859-1" >> /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen

locale-gen
emerge --ag sys-kernel/linux-firmware
echo "sys-kernel/installkernel dracut uki" >> /etc/portage/package.use/installkernel
emerge --ask sys-kernel/gentoo-kernel-bin
echo 'uefi="yes"' >>  /etc/dracut.conf
echo 'kernel_cmdline="rd.luks.name='$luks_root_uuid'=cryptroot root=/dev/'$hostname'/root"' >> /etc/dracut.conf


echo -e "UUID=$luks_root_uuid	/	$fs_type	defaults,noatime	0	1" >> /etc/fstab
if [[ ! -z $root_part_size ]]; then

	echo -e "UUID=$luks_home_uuid	/home	$fs_type	defaults,noatime	0	2" >> /etc/fstab
fi

	echo -e "UUID=$boot_uuid	  /efi	    vfat	umask=0077	0	2" >> /etc/fstab

echo $hostname > /etc/hostname

echo "$root_pw\n$root_pw" | passwd -q root

emerge --ask sys-boot/efibootmgr

mkdir -p /efi/efi/gentoo
cp /boot/vmlinuz-* /efi/efi/gentoo/bzImage.efi 
efibootmgr --create --disk /dev/$disk --part 1 --label "gentoo_uefi" --loader "\efi\gentoo\bzImage.efi"



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
