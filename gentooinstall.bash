#!/bin/bash
#read this script carefully before use it!!


username="k2"

luks_pw="123" #password for disk encryption

#root_pw="123" #root password

#user_pw="123" #user password

efi_part_size="512M"

root_part_size="" # if it is empty it will create only a root partition. (and doesnt create a home partition with the remaining space)

hostname="xpto"

fs_type="btrfs" #xfs or ext4

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
echo $luks_pw | cryptsetup -q luksFormat --type luks1 $luks_part
echo $luks_pw | cryptsetup open $luks_part crypt

if [[ $fs_type != "btrfs" ]]; then
vgcvgcreate $hostname /dev/mapper/crypt
else
mkfs.btrfs -L $hostname /dev/mapper/crypt
fi

if [[ $fs_type != "btrfs" && -z $root_part_size ]]; then
	vgcreate $hostname /dev/mapper/crypt
	lvcreate --name root -l 100%FREE $hostname
	mkfs.$fs_type -qL root /dev/$hostname/root
	mount /dev/$hostname/root /mnt/gentoo
elif [[ fs_type != "btrfs" && ! -z $root_part_size ]]; then
	lvcreate --name root -L $root_part_size $hostname
	lvcreate --name home -l 100%FREE $hostname
	mkfs.$fs_type -qL root /dev/$hostname/root
	mkfs.$fs_type -qL home /dev/$hostname/home
	mount /dev/$hostname/root /mnt/gentoo
	mkdir -p /mnt/gentoo/home
	mount /dev/$hostname/home /mnt/gentoo/home

fi

if [[ $fs_type == "btrfs"  ]]; then

	$root_part_size=""
	BTRFS_OPTS="noatime,compress,space_cache=v2,discard=async,ssd"
	mount -o $BTRFS_OPTS /dev/mapper/crypt /mnt/gentoo
	btrfs subvolume create /mnt/gentoo/@
	btrfs subvolume create /mnt/gentoo/@home
	btrfs subvolume create /mnt/gentoo/@log
    btrfs subvolume create /mnt/gentoo/@cache
    btrfs subvolume create /mnt/gentoo/@snapshots
    umount /mnt/gentoo

    mount -o $BTRFS_OPTS,subvol=@ /dev/mapper/crypt /mnt/gentoo
	mkdir -p /mnt/gentoo/{home,.snapshots,var/log,var/cache}
	mount -o $BTRFS_OPTS,subvol=@home /dev/mapper/crypt /mnt/gentoo/home
	mount -o $BTRFS_OPTS,subvol=@log /dev/mapper/crypt /mnt/gentoo/var/log
	mount -o $BTRFS_OPTS,subvol=@cache /dev/mapper/crypt /mnt/gentoo/var/cache
	mount -o $BTRFS_OPTS,subvol=@snapshots /dev/mapper/crypt /mnt/gentoo/.snapshots

fi

home_uuid=$(blkid -o value -s UUID /dev/mapper/$hostname-home)
root_uuid=$(blkid -o value -s UUID /dev/mapper/$hostname-root)
luks_uuid=$(blkid -o value -s UUID $disk'2')
boot_uuid=$(blkid -o value -s UUID $disk'1')
ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/crypt)

mkfs.vfat -F 32 $efi_part
mkdir -p /mnt/gentoo/efi/EFI
mount $efi_part /mnt/gentoo/efi
echo -e "UUID=$boot_uuid	/efi 	    vfat	umask=0077	0	2" >> /mnt/gentoo/etc/fstab

if [[ $fs_type != "btrfs" && ! -z $root_part_size ]]; then
	echo -e "UUID=$root_uuid	/	$fs_type	defaults,noatime	0	1" >> /mnt/gentoo/etc/fstab
	echo -e "UUID=$home_uuid	/home	$fs_type	defaults,noatime	0	2" >> /mnt/gentoo/etc/fstab
elif [[ $fs_type != "btrfs" &&  -z $root_part_size ]]; then
	echo -e "UUID=$root_uuid	/	$fs_type	defaults,noatime	0	1" >> /mnt/gentoo/etc/fstab
else
	echo -e "UUID=$ROOT_UUID / btrfs $BTRFS_OPTS,subvol=@ 0 1
	UUID=$ROOT_UUID /home btrfs $BTRFS_OPTS,subvol=@home 0 2
	UUID=$ROOT_UUID /var/log btrfs $BTRFS_OPTS,subvol=@log 0 2
	UUID=$ROOT_UUID /var/cache btrfs $BTRFS_OPTS,subvol=@cache 0 2
	UUID=$ROOT_UUID /.snapshots btrfs $BTRFS_OPTS,subvol=@snapshots 0 2" >> /mnt/gentoo/etc/fstab
fi
 
#STAGE FILE

cd /mnt/gentoo
links https://mirrors.ptisp.pt/gentoo/releases/amd64/autobuilds
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

#INSTALL BASE SYSTEM

mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run

#chroot /mnt/gentoo/gentoo source /etc/profile

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
chroot /mnt/gentoo/ emerge-webrsync && getuto

echo "[gentoobinhost]" > /mnt/gentoo/etc/portage/binrepos.conf/gentoobinhost.conf
echo "priority = 9999" >> /mnt/gentoo/etc/portage/binrepos.conf/gentoobinhost.conf
echo "sync-uri = https://mirrors.ptisp.pt/gentoo/releases/amd64/binpackages/23.0/x86-64/" >> /mnt/gentoo/etc/portage/binrepos.conf/gentoobinhost.conf


# sed -i 's@COMMOM_FLAGS="-02 -pipe"@COMMON_FLAGS="-march=native -O2 -pipe"@g' /mnt/gentoo/gentoo/etc/portage/make.conf
#echo 'MAKEOPTS="-j4 -l4"' >> /mnt/gentoo/gentoo/etc/portage/make.conf

echo 'FEATURES="${FEATURES} getbinpkg binpkg-request-signature"' >> /mnt/gentoo/etc/portage/make.conf
echo 'BINPKG_FORMAT="gpkg"' >> /mnt/gentoo/etc/portage/make.conf

 echo 'ACCEPT_LICENSE="*"' >> /mnt/gentoo/etc/portage/make.conf
#echo 'VIDEO_CARDS="qxl"' >> /mnt/gentoo/etc/portage/make.conf >> /mnt/gentoo/etc/portage/make.conf
echo 'GENTOO_MIRRORS="https://mirrors.ptisp.pt/gentoo/"' >> /mnt/gentoo/etc/portage/make.conf
#openrc
echo "Europe/Lisbon" > /mnt/gentoo/etc/timezone
#chroot /mnt/gentoo emerge --config sys-libs/timezone-data
#systemd
#ln -sf ../usr/share/zoneinfo/Europe/Lisbon /mnt/gentoo/etc/localtime
echo 'GRUB_PLATFORMS="efi-64"' >> /mnt/gentoo/etc/portage/make.conf
#echo 'USE="pulseaudio"' >> /mnt/gentoo/etc/portage/make.conf
echo 'USE="pulseaudio secureboot"' >> /mnt/gentoo/etc/portage/make.conf

# Secure Boot signing keys
echo 'SECUREBOOT_SIGN_KEY="/root/secureboot/MOK.pem"' >> /mnt/gentoo/etc/portage/make.conf
echo 'SECUREBOOT_SIGN_CERT="/root/secureboot/MOK.pem"' >> /mnt/gentoo/etc/portage/make.conf


echo "en_US ISO-8859-1" >> /mnt/gentoo/etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /mnt/gentoo/etc/locale.gen
chroot /mnt/gentoo/ locale-gen

 
 #KERNEL CONFIG

 chroot /mnt/gentoo emerge -avgq sys-kernel/linux-firmware sys-firmware/intel-microcode
  #openrc
 #uki
 #echo "sys-kernel/installkernel dracut uki" > /mnt/gentoo/etc/portage/package.use/system
 #echo "sys-apps/systemd-utils boot kernel-install" >> /mnt/gentoo/etc/portage/package.use/system
 #grub
 echo "sys-fs/lvm2 lvm" > /mnt/gentoo/etc/portage/package.use/system
 echo "sys-kernel/installkernel grub dracut" >> /mnt/gentoo/etc/portage/package.use/system
 echo "sys-apps/dbus X" >> /mnt/gentoo/etc/portage/package.use/system
 #systemd systemd-boot
 #echo "sys-kernel/installkernel systemd-boot" > /mnt/gentoo/etc/portage/package.use/system
 #echo "sys-fs/lvm2 lvm" >> /mnt/gentoo/etc/portage/package.use/system
 #echo "sys-apps/systemd boot cryptsetup" >> /mnt/gentoo/etc/portage/package.use/system
 

#xfs or ext4
if [[ fs_type != "btrfs" ]]; then
echo "quiet rd.luks.uuid='$luks_uuid' root=UUID='$root_uuid' rd.lvm.vg='$hostname' rd.luks.allow-discards" > /mnt/gentoo/etc/cmdline
else
#btrfs
 echo "root=UUID='$ROOT_UUID' apparmor=1 security=apparmor quiet" > /mnt/gentoo/etc/cmdline
fi

#systemd
#  chroot /mnt/gentoo systemd-machine-id-setup
#  chroot /mnt/gentoo systemd-firstboot --prompt
#  chroot /mnt/gentoo systemctl preset-all --preset-mode=enable-only
#  chroot /mnt/gentoo systemctl preset-all
#  chroot /mnt/gentoo bootctl install
# echo -e "UUID=$boot_uuid	/efi 	    vfat	umask=0077	0	2" >> /mnt/gentoo/etc/fstab
 
 #mkdir -p /mnt/gentoo/gentoo/etc/dracut.conf.d
 #touch /mnt/gentoo/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'hostonly="yes"' >>  /mnt/gentoo/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'add_dracutmodules+=" lvm crypt dm rootfs-block systemd "' >>  /mnt/gentoo/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'uefi="yes"' >>  /mnt/gentoo/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'kernel_cmdline="quiet lsm=capability,landlock,yama,apparmor rd.luks.uuid='$luks_uuid' root=UUID='$root_uuid' rd.lvm.vg='$hostname' rd.luks.allow-discards"' >> /mnt/gentoo/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'compress="gzip"' >>  /mnt/gentoo/gentoo/etc/dracut.conf.d/10-dracut.conf
 #echo 'early_microcode="yes"'  >>  /mnt/gentoo/gentoo/etc/dracut.conf.d/10-dracut.conf
 #mkdir -p /mnt/gentoo/gentoo/efi/EFI/Linux

#CONFIG SYSTEM
#secureboot shim
chroot /mnt emerge -avgq sys-boot/shim sys-boot/mokutil

chroot /mnt/gentoo mkdir /root/secureboot

chroot /mnt/gentoo openssl req -new -nodes -utf8 -sha256 -x509 -outform PEM \
    -out /root/secureboot/MOK.pem -keyout /root/secureboot/MOK.pem \
    -subj "/CN=<$username>/"


chroot /mnt/gentoo openssl x509 -inform pem -in /root/secureboot/MOK.pem -outform der -out /boot/sbcert.der

echo $hostname > /mnt/gentoo/etc/hostname

#openrc
chroot /mnt/gentoo emerge -avgq sudo lvm2 cryptsetup efibootmgr iwd # systemd-utils apparmor apparmor-profiles apparmor-utils iwd doas cronie sysklogd dhcpcd
#systemd
#chroot /mnt/gentoo emerge -avgq sudo # iwd apparmor apparmor-profiles apparmor-utils

mkdir -p /mnt/gentoo/etc/iwd

echo -e "[General]
EnableNetworkConfiguration=true
[Network]
RoutePriorityOffset=200
NameResolvingService=none
EnableIPv6=false" > /mnt/gentoo/etc/iwd/main.conf

#resolv.conf --quad9
echo -e "nameserver 9.9.9.11
nameserver 149.112.112.11" > /mnt/gentoo/etc/resolv.conf


#chroot /mnt/gentoo/gentoo/ emerge -aunDN @world
chroot /mnt/gentoo emerge -avgq sys-kernel/gentoo-kernel-bin

chroot /mnt/gentoo cp /usr/share/shim/BOOTX64.EFI /efi/EFI/gentoo/shimx64.efi
chroot /mnt/gentoo cp /usr/share/shim/mmx64.efi /efi/EFI/gentoo/mmx64.efi
chroot /mnt/gentoo cp /usr/lib/grub/grub-x86_64.efi.signed /efi/EFI/gentoo/grubx64.efi

chroot /mnt/gentoo efibootmgr --disk /dev/sda --part 1 --create -L "GRUB via Shim" -l '\EFI\gentoo\shimx64.efi'

echo "GRUB_CFG=/efi/EFI/gentoo/grub.cfg" >> /mnt/env.d/99grub


#CONFIG BOOTLOADER - uefi
 #cp /mnt/gentoo/gentoo/efi/EFI/Linux/*dist.efi /mnt/gentoo/gentoo/efi/EFI/Linux/linux.efi
 
 #create uefi boot entry
 #chroot /mnt/gentoo/gentoo efibootmgr -c -d $disk -p 1 -L "Gentoo" -l "\EFI\Linux\linux.efi"


#add services
chroot /mnt/gentoo rc-update add dmcrypt boot
chroot /mnt/gentoo rc-update add lvm boot
#chroot /mnt/gentoo rc-update add dhcpcd default
chroot /mnt/gentoo rc-update add iwd default
#chroot /mnt/gentoo rc-update add apparmor boot
#chroot /mnt/gentoo/gentoo rc-update add firewalld boot
#chroot /mnt/gentoo/gentoo rc-update add cronie default
#chroot /mnt/gentoo/gentoo rc-update add sysklogd default
#chroot /mnt/gentoo/gentoo rc-update add auditd default

#systemd
# chroot /mnt/gentoo systemctl enable lvm2-monitor.service
#
# chroot /mnt/gentoo useradd -m -G wheel -s /bin/bash $username

#doas
#echo "permit keepenv :wheel" > /mnt/gentoo/gentoo/etc/doas.conf
#chroot /mnt/gentoo/gentoo chown -c root:root /etc/doas.conf
#chroot /mnt/gentoo/gentoo chmod -c 0400 /etc/doas.conf

#touch /mnt/gentoo/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
#chmod +x /mnt/gentoo/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
#echo "#!/bin/sh" > /mnt/gentoo/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
#echo "cp /efi/EFI/Linux/*dist.efi /efi/EFI/Linux/linux.efi" >> /mnt/gentoo/gentoo/etc/kernel/postinst.d/95-uefi-boot.install

#secure boot
# if [[ ! -z $secure_boot ]]; then
# chroot /mnt/gentoo emerge -avgq sbctl
# chroot /mnt/gentoo sbctl create-keys
# chroot /mnt/gentoo sbctl enroll-keys -m -i
# chroot /mnt/gentoo sbctl sign -s /mnt/gentoo/efi/EFI/Linux/linux.efi
# echo "sbctl sign -s /efi/EFI/Linux/linux.efi" >> /mnt/gentoo/etc/kernel/postinst.d/95-uefi-boot.install
# fi
#chroot /mnt/gentoo emerge -avgq grub
mkdir /mnt/gentoo/etc/dracut.conf.d
touch /mnt/gentoo/etc/dracut.conf.d/chave
echo GRUB_ENABLE_CRYPTODISK=y >> /mnt/gentoo/etc/default/grub
dd bs=1 count=64 if=/dev/urandom of=/mnt/gentoo/boot/volume.key
echo $luks_pw | cryptsetup luksAddKey $disk'2' /mnt/gentoo/boot/volume.key
chroot /mnt/gentoo chmod 000 /boot/volume.key
chroot /mnt/gentoo chmod -R g-rwx,o-rwx /boot
echo "crypt UUID=$luks_uuid /boot/volume.key luks" >> /mnt/gentoo/etc/crypttab
echo 'install_items+=" /boot/volume.key /etc/crypttab "' > /mnt/gentoo/etc/dracut.conf.d/chave
chroot /mnt/gentoo grub-install --efi-directory=/efi
chroot /mnt/gentoo grub-mkconfig -o /efi/EFI/gentoo/grub.cfg
chroot /mnt/gentoo useradd -m -G wheel -s /bin/bash $username
#chroot /mnt/gentoo/gentoo passwd root
#chroot /mnt/gentoo/gentoo passwd $username

# cat << EOF | chroot /mnt/gentoo
# echo "$root_pw\n$root_pw" | passwd -q root
# echo "$user_pw\n$user_pw" | passwd -q $username
# EOF

chroot /mnt/gentoo mokutil --import /boot/sbcert.der
chroot /mnt/gentoo passwd root

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
