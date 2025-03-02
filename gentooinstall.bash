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

fs_type="xfs" #xfs or ext4

disk="/dev/vda" #or /dev/vda for virt-manager

secure_boot="yes" # better to leave this empty  

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
echo $luks_pw | cryptsetup -q luksFormat $luks_part
echo $luks_pw | cryptsetup --type luks2 open $luks_part crypt
vgcreate $hostname /dev/mapper/crypt

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
#links https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds
wget https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds/20250223T170333Z/stage3-amd64-desktop-systemd-20250223T170333Z.tar.xz
#wget https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds/20250225T170409Z/stage3-amd64-desktop-openrc-20240225T170409Z.tar.xz
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

#INSTALL BASE SYSTEM

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run 

chroot /mnt/gentoo source /etc/profile

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
chroot /mnt/gentoo/ emerge-webrsync && getuto

echo "[gentoobinhost]" > /mnt/gentoo/etc/portage/binrepos.conf/gentoobinhost.conf
echo "priority = 1" >> /mnt/gentoo/etc/portage/binrepos.conf/gentoobinhost.conf
echo "sync-uri = https://mirrors.ptisp.pt/gentoo/releases/amd64/binpackages/23.0/x86-64/" >> /mnt/gentoo/etc/portage/binrepos.conf/gentoobinhost.conf


sed -i 's@COMMOM_FLAGS="-02 -pipe"@COMMON_FLAGS="-march=native -O2 -pipe"@g' /mnt/gentoo/etc/portage/make.conf
echo 'MAKEOPTS="-j4 -l4"' >> /mnt/gentoo/etc/portage/make.conf

echo 'FEATURES="${FEATURES} getbinpkg binpkg-request-signature"' >> /mnt/gentoo/etc/portage/make.conf
echo 'BINPKG_FORMAT="gpkg"' >> /mnt/gentoo/etc/portage/make.conf

 echo 'ACCEPT_LICENSE="-* @FREE @BINARY-REDISTRIBUTABLE"' >> /mnt/gentoo/etc/portage/make.conf
#echo 'VIDEO_CARDS="qxl"' >> /mnt/gentoo/etc/portage/make.conf >> /mnt/gentoo/etc/portage/make.conf
echo 'GENTOO_MIRRORS="https://mirrors.ptisp.pt/gentoo/"' >> /mnt/gentoo/etc/portage/make.conf
#openrc
echo "Europe/Lisbon" > /mnt/gentoo/etc/timezone
chroot /mnt/gentoo/ emerge --config sys-libs/timezone-data

echo "en_US ISO-8859-1" >> /mnt/gentoo/etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /mnt/gentoo/etc/locale.gen
chroot /mnt/gentoo/ locale-gen

 
 #KERNEL CONFIG

 #chroot /mnt/gentoo emerge -avgq sys-kernel/linux-firmware sys-firmware/intel-microcode
  #openrc
 #echo "sys-kernel/installkernel dracut uki" > /mnt/gentoo/etc/portage/package.use/system
 #echo "sys-fs/lvm2 lvm" >> /mnt/gentoo/etc/portage/package.use/system
 #echo "sys-apps/systemd-utils boot kernel-install" >> /mnt/gentoo/etc/portage/package.use/system
 #systemd
 echo "sys-kernel/installkernel dracut uki" > /mnt/gentoo/etc/portage/package.use/system
 echo "sys-fs/lvm2 lvm" >> /mnt/gentoo/etc/portage/package.use/system
 echo "sys-apps/systemd boot" >> /mnt/gentoo/etc/portage/package.use/system
 chroot /mnt/gentoo/ emerge -avgq installkernel

 chroot /mnt/gentoo/ systemd-machine-id-setup
 chroot /mnt/gentoo/ systemd-firstboot --prompt
 chroot /mnt/gentoo/ systemctl preset-all --preset-mode=enable-only
 chroot /mnt/gentoo/ systemctl preset-all
 #chroot /mnt/gentoo/ bootctl install

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
 echo 'hostonly="yes"' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 echo 'add_dracutmodules+=" lvm crypt dm rootfs-block systemd-cryptsetup systemd-ask-password "' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 echo 'uefi="yes"' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 echo 'kernel_cmdline="quiet lsm=capability,landlock,yama,apparmor rd.luks.uuid='$luks_uuid' root=UUID='$root_uuid' rd.lvm.vg='$hostname' rd.luks.allow-discards"' >> /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 echo 'compress="gzip"' >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 echo 'early_microcode="yes"'  >>  /mnt/gentoo/etc/dracut.conf.d/10-dracut.conf
 mkdir -p /mnt/gentoo/efi/EFI/Linux

#CONFIG SYSTEM
 
echo $hostname > /mnt/gentoo/etc/hostname

#openrc
#chroot /mnt/gentoo/ emerge -avgq lvm2 systemd-utils cryptsetup efibootmgr apparmor apparmor-profiles apparmor-utils iwd doas cronie sysklogd
#systemd
chroot /mnt/gentoo/ emerge -avgq lvm2 cryptsetup efibootmgr iwd doas

mkdir -p /mnt/gentoo/etc/iwd

touch /mnt/gentoo/etc/iwd/main.conf
echo "[General]" > /mnt/gentoo/etc/iwd/main.conf
echo "EnableNetworkConfiguration=true" >> /mnt/gentoo/etc/iwd/main.conf
echo "[Network]" >> /mnt/gentoo/etc/iwd/main.conf
#echo "RoutePriorityOffset=200" >> /mnt/gentoo/etc/iwd/main.conf
echo "NameResolvingService=none" >> /mnt/gentoo/etc/iwd/main.conf
#echo "EnableIPv6=false" >> /mnt/gentoo/etc/iwd/main.conf

#resolv.conf --quad9
echo "nameserver 9.9.9.11" > /mnt/gentoo/etc/resolv.conf
echo "nameserver 149.112.112.11" >> /mnt/gentoo/etc/resolv.conf


#chroot /mnt/gentoo/ emerge -aunDN @world
chroot /mnt/gentoo/ emerge -avgq sys-kernel/gentoo-kernel-bin
#CONFIG BOOTLOADER - uefi

 cp /mnt/gentoo/efi/EFI/Linux/*dist.efi /mnt/gentoo/efi/EFI/Linux/linux.efi
 
 #create uefi boot entry
 chroot /mnt/gentoo efibootmgr -c -d $disk -p 1 -L "Gentoo" -l "\EFI\Linux\linux.efi"


#add services
#chroot /mnt/gentoo/ rc-update add dmcrypt boot
#chroot /mnt/gentoo/ rc-update add lvm boot
#chroot /mnt/gentoo/ rc-update add apparmor boot
#chroot /mnt/gentoo rc-update add firewalld boot
#chroot /mnt/gentoo rc-update add cronie default
#chroot /mnt/gentoo rc-update add sysklogd default
#chroot /mnt/gentoo rc-update add auditd default

#systemd
chroot /mnt/gentoo systemctl enable lvm2-monitor.service

chroot /mnt/gentoo useradd -m -G wheel -s /bin/bash $username

#doas
echo "permit keepenv :wheel" > /mnt/gentoo/etc/doas.conf
chroot /mnt/gentoo chown -c root:root /etc/doas.conf
chroot /mnt/gentoo chmod -c 0400 /etc/doas.conf

touch /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
chmod +x /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
echo "#!/bin/sh" > /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
echo "cp /efi/EFI/Linux/*dist.efi /efi/EFI/Linux/linux.efi" >> /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install

#secure boot
if [[ ! -z $secure_boot ]]; then
chroot /mnt/gentoo emerge -avgq sbctl
chroot /mnt/gentoo sbctl create-keys
chroot /mnt/gentoo sbctl enroll-keys -m -i
chroot /mnt/gentoo sbctl sign -s /mnt/gentoo/efi/EFI/Linux/linux.efi
echo "sbctl sign -s /efi/EFI/Linux/linux.efi" >> /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
fi


chroot /mnt/gentoo echo "$root_pw\n$root_pw" | passwd -q root
chroot /mnt/gentoo echo "$user_pw\n$user_pw" | passwd -q $username


echo -e "\nUnmount gentoo installation and reboot?(y/n)\n"
read tmp
if [[ $tmp == "y" ]]; then
	exit
        
	 	umount -l /mnt/gentoo/dev{/shm,/pts,}
 	umount -R /mnt/gentoo
# 	reboot 
  shutdown -r now
fi

echo -e "\nFinish\n"
