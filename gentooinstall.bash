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

disk="/dev/sda" #or /dev/vda for virt-manager


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
echo $luks_pw | cryptsetup -q --cipher aes-xts-plain64 --key-size 256 --hash sha256 --iter-time 5000 --use-random --type luks2 luksFormat /dev/sda3
echo $luks_pw | cryptsetup --type luks2 open /dev/sda3 home



mkfs.xfs -qL root /dev/sda2

mkfs.ext4 -qL home /dev/mapper/home

mount /dev/sda2 /mnt/gentoo
mount /dev/mapper/home /mnt/gentoo/home


#STAGE FILE

cd /mnt/gentoo

gpg --import /usr/share/openpgp-keys/gentoo-release.asc
wget https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds/current-stage3-amd64-openrc/stage3-amd64-openrc-20240204T134829Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner


#arch-chroot /mnt/gentoo




#INSTALL BASE SYSTEM

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/



mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run 

cat << EOF | chroot /mnt/gentoo /bin/bash
#<do anything as gentoo wiki explain or according your needs>

source /etc/profile 
export PS1="(chroot) ${PS1}"

mkfs.vfat $efi_part
mkdir -p /efi
mount $efi_part /efi

 mkdir --parents /etc/portage/repos.conf
 cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
emerge-webrsync
 sed -i 's@"-02 -pipe"@"-march=native -O2 -pipe"@g' /etc/portage/make.conf
 echo "MAKEOPTS="-j4 -l4" >> /etc/portage/make.conf
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
 
 env-update && source /etc/profile && export PS1="(chroot) ${PS1}"


#KERNEL CONFIG

 emerge sys-kernel/linux-firmware
 emerge sys-firmware/intel-microcode
 echo "sys-kernel/installkernel dracut uki" >> /etc/portage/package.use/installkernel
 
 echo 'uefi="yes"' >>  /etc/dracut.conf
 echo 'kernel_cmdline="root=/dev/sda2 apparmor=1 security=apparmor"' >> /etc/dracut.conf

mkdir -p /efi/EFI/Linux

#CONFIG SYSTEM

 echo -e "/dev/sda2	/	xfs	defaults,noatime	0	1" >> /etc/fstab
 echo -e "/dev/mapper/home	/home	ext4	defaults,noatime	0	2" >> /etc/fstab
 echo -e "/dev/sda1  /efi	    vfat	umask=0077	0	2" >> /etc/fstab

 echo $hostname > /etc/hostname

 echo "$root_pw\n$root_pw" | passwd -q root

 emerge sys-fs/xfsprogs
emerge cryptsetup
emerge systemd-utils

echo "target=home" >> /etc/conf.d/dmcrypt
echo 'source="/dev/sda3"' >> /etc/conf.d/dmcrypt
emerge -aunDN @world
emerge sys-kernel/gentoo-kernel-bin
#CONFIG BOOTLOADER

 emerge sys-boot/efibootmgr

cp /efi/EFI/Linux/*-dist.efi linux.efi
 
 efibootmgr -c --disk /dev/$disk --part 1 -l "\EFI\Linux\linux.efi"


rc-update add dmcrypt boot


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
