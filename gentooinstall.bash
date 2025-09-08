#!/bin/bash
#read this script carefully before use it!!


username="k2"

luks_pw="1" #password for disk encryption

#root_pw="123" #root password

#user_pw="123" #user password

efi_part_size="512M"

root_part_size="" # if it is empty it will create only a root partition. (and doesnt create a home partition with the remaining space)

hostname="xpto"

fs_type="xfs" #xfs or ext4

disk="/dev/sda" #or /dev/vda for virt-manager

secure_boot="" # better to leave this empty

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
wipefs -aqf $disk

#dd if=/dev/zero of=/dev$disk bs=16M count=500

printf 'label: gpt\n, %s, U, *\n, , L\n' "$efi_part_size" | sfdisk -qf "$disk"

#Create LUKS2 encrypted partition
#cryptsetup benchmark   to find the best cypher for your pc
echo $luks_pw | cryptsetup -q luksFormat $luks_part
echo $luks_pw | cryptsetup $luks_part crypt_"${luks_part/'/dev/'}"

vgcreate $hostname /dev/mapper/crypt_"${luks_part/'/dev/'}"

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

if [[ ! -z $root_part_size ]]; then
	mkdir -p /mnt/home
	mount /dev/$hostname/home /mnt/home
fi

	mkfs.vfat $efi_part
	mkdir -p /mnt/efi
	mount $efi_part /mnt/efi
 

 
#STAGE FILE

cd /mnt
links https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds
#wget https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds/20250223T170333Z/stage3-amd64-desktop-systemd-20250223T170333Z.tar.xz
#wget https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds/20250225T170409Z/stage3-amd64-desktop-openrc-20240225T170409Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

#INSTALL BASE SYSTEM

mount --types proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --make-rslave /mnt/sys
mount --rbind /dev /mnt/dev
mount --make-rslave /mnt/dev
mount --bind /run /mnt/run
mount --make-slave /mnt/run

#chroot /mnt/gentoo source /etc/profile

cp --dereference /etc/resolv.conf /mnt/etc/

mkdir --parents /mnt/etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /mnt/etc/portage/repos.conf/gentoo.conf
chroot /mnt/ emerge-webrsync && getuto

echo "[gentoobinhost]" > /mnt/etc/portage/binrepos.conf/gentoobinhost.conf
echo "priority = 9999" >> /mnt/etc/portage/binrepos.conf/gentoobinhost.conf
echo "sync-uri = https://mirrors.ptisp.pt/gentoo/releases/amd64/binpackages/23.0/x86-64/" >> /mnt/etc/portage/binrepos.conf/gentoobinhost.conf


# sed -i 's@COMMOM_FLAGS="-02 -pipe"@COMMON_FLAGS="-march=native -O2 -pipe"@g' /mnt/gentoo/etc/portage/make.conf
#echo 'MAKEOPTS="-j4 -l4"' >> /mnt/gentoo/etc/portage/make.conf

echo 'FEATURES="${FEATURES} getbinpkg binpkg-request-signature"' >> /mnt/etc/portage/make.conf
echo 'BINPKG_FORMAT="gpkg"' >> /mnt/etc/portage/make.conf

 echo 'ACCEPT_LICENSE="*"' >> /mnt/etc/portage/make.conf
#echo 'VIDEO_CARDS="qxl"' >> /mnt/etc/portage/make.conf >> /mnt/etc/portage/make.conf
echo 'GENTOO_MIRRORS="https://mirrors.ptisp.pt/gentoo/"' >> /mnt/etc/portage/make.conf
#openrc
#echo "Europe/Lisbon" > /mnt/gentoo/etc/timezone
#chroot /mnt/gentoo/ emerge --config sys-libs/timezone-data
#systemd
ln -sf ../usr/share/zoneinfo/Europe/Lisbon /mnt/etc/localtime

echo "en_US ISO-8859-1" >> /mnt/etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /mnt/etc/locale.gen
chroot /mnt/ locale-gen

 
 #KERNEL CONFIG

 chroot /mnt emerge -avgq sys-kernel/linux-firmware sys-firmware/intel-microcode
  #openrc
 #echo "sys-kernel/installkernel dracut uki" > /mnt/gentoo/etc/portage/package.use/system
 #echo "sys-fs/lvm2 lvm" >> /mnt/gentoo/etc/portage/package.use/system
 #echo "sys-apps/systemd-utils boot kernel-install" >> /mnt/gentoo/etc/portage/package.use/system
 #systemd
 #echo "sys-kernel/installkernel dracut uki" > /mnt/gentoo/etc/portage/package.use/system
 echo "sys-kernel/installkernel systemd-boot" > /mnt/etc/portage/package.use/system
 echo "sys-fs/lvm2 lvm" >> /mnt/etc/portage/package.use/system
 echo "sys-apps/systemd boot cryptsetup" >> /mnt/etc/portage/package.use/system
 
 chroot /mnt emerge -avgq installkernel systemd
 
 echo "quiet rd.luks.uuid='$luks_uuid' root=UUID='$root_uuid' rd.lvm.vg='$hostname' rd.luks.allow-discards" > /mnt/etc/cmdline
 
 chroot /mnt systemd-machine-id-setup
 chroot /mnt systemd-firstboot --prompt
 chroot /mnt systemctl preset-all --preset-mode=enable-only
 chroot /mnt systemctl preset-all
 chroot /mnt bootctl install

home_uuid=$(blkid -o value -s UUID /dev/mapper/$hostname-home)
root_uuid=$(blkid -o value -s UUID /dev/mapper/$hostname-root)
luks_uuid=$(blkid -o value -s UUID $disk'2')
boot_uuid=$(blkid -o value -s UUID $disk'1')

echo -e "UUID=$root_uuid	/	$fs_type	defaults,noatime	0	1" >> /mnt/etc/fstab
if [[ ! -z $root_part_size ]]; then

echo -e "UUID=$home_uuid	/home	$fs_type	defaults,noatime	0	2" >> /mnt/etc/fstab
fi

echo -e "UUID=$boot_uuid	/efi 	    vfat	umask=0077	0	2" >> /mnt/etc/fstab

 
 #mkdir -p /mnt/gentoo/etc/dracut.conf.d
 #touch /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'hostonly="yes"' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'add_dracutmodules+=" lvm crypt dm rootfs-block systemd "' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'uefi="yes"' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'kernel_cmdline="quiet lsm=capability,landlock,yama,apparmor rd.luks.uuid='$luks_uuid' root=UUID='$root_uuid' rd.lvm.vg='$hostname' rd.luks.allow-discards"' >> /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'compress="gzip"' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'early_microcode="yes"'  >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 #mkdir -p /mnt/gentoo/efi/EFI/Linux

#CONFIG SYSTEM
 
#echo $hostname > /mnt/gentoo/etc/hostname

#openrc
#chroot /mnt/gentoo/ emerge -avgq lvm2 systemd-utils cryptsetup efibootmgr apparmor apparmor-profiles apparmor-utils iwd doas cronie sysklogd
#systemd
chroot /mnt emerge -avgq iwd sudo apparmor apparmor-profiles apparmor-utils

mkdir -p /mnt/etc/iwd

echo -e "[General]
EnableNetworkConfiguration=true
[Network]
RoutePriorityOffset=200
NameResolvingService=none
EnableIPv6=false" > /mnt/etc/iwd/main.conf

#resolv.conf --quad9
echo -e "nameserver 9.9.9.11
nameserver 149.112.112.11" > /mnt/etc/resolv.conf


#chroot /mnt/gentoo/ emerge -aunDN @world
chroot /mnt emerge -avgq sys-kernel/gentoo-kernel-bin
#CONFIG BOOTLOADER - uefi

 #cp /mnt/gentoo/efi/EFI/Linux/*dist.efi /mnt/gentoo/efi/EFI/Linux/linux.efi
 
 #create uefi boot entry
 #chroot /mnt/gentoo efibootmgr -c -d $disk -p 1 -L "Gentoo" -l "\EFI\Linux\linux.efi"


#add services
#chroot /mnt/gentoo/ rc-update add dmcrypt boot
#chroot /mnt/gentoo/ rc-update add lvm boot
#chroot /mnt/gentoo/ rc-update add apparmor boot
#chroot /mnt/gentoo rc-update add firewalld boot
#chroot /mnt/gentoo rc-update add cronie default
#chroot /mnt/gentoo rc-update add sysklogd default
#chroot /mnt/gentoo rc-update add auditd default

#systemd
chroot /mnt systemctl enable lvm2-monitor.service

chroot /mnt useradd -m -G wheel -s /bin/bash $username

#doas
#echo "permit keepenv :wheel" > /mnt/gentoo/etc/doas.conf
#chroot /mnt/gentoo chown -c root:root /etc/doas.conf
#chroot /mnt/gentoo chmod -c 0400 /etc/doas.conf

#touch /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
#chmod +x /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
#echo "#!/bin/sh" > /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
#echo "cp /efi/EFI/Linux/*dist.efi /efi/EFI/Linux/linux.efi" >> /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install

#secure boot
# if [[ ! -z $secure_boot ]]; then
# chroot /mnt emerge -avgq sbctl
# chroot /mnt sbctl create-keys
# chroot /mnt sbctl enroll-keys -m -i
# chroot /mnt sbctl sign -s /mnt/efi/EFI/Linux/linux.efi
# echo "sbctl sign -s /efi/EFI/Linux/linux.efi" >> /mnt/etc/kernel/postinst.d/95-uefi-boot.install
# fi


#chroot /mnt/gentoo passwd root
#chroot /mnt/gentoo passwd $username



echo -e "\nUnmount gentoo installation and reboot?(y/n)\n"
read tmp
if [[ $tmp == "y" ]]; then
	exit
        
	 	umount -l /mnt/dev{/shm,/pts,}
 	umount -R /mnt
# 	reboot 
  shutdown -r now
fi

echo -e "\nFinish\n"
