. /lib/functions/system.sh


RAMFS_COPY_BIN='fw_setenv'
RAMFS_COPY_DATA='/etc/fw_env.config /var/lock/fw_printenv.lock /tmp/downgrade'

sw8_env_setup() {
    local ubifile=$(board_name)
    local active=$1
    cat > /tmp/env_tmp << EOF
owrt_slotactive=$active
owrt_bootcount=0
bootfile=${ubifile}.ubi
owrt_bootcountcheck=if test \$owrt_bootcount > 4; then run owrt_tftprecover; fi; if test \$owrt_bootcount = 3; then run owrt_slotswap; else echo bootcountcheck successfull; fi
owrt_bootinc=if test \$owrt_bootcount < 5; then echo save env part; setexpr owrt_bootcount \${owrt_bootcount} + 1 && saveenv; else echo save env skipped; fi; echo current bootcount: \$owrt_bootcount
bootcmd=run owrt_bootinc && run owrt_bootcountcheck && run owrt_slotselect && run owrt_bootlinux
owrt_bootlinux=echo booting linux... && ubi part fs && ubi read 0x44000000 kernel && bootm; reset
owrt_setslot0=setenv bootargs console=ttyMSM0,115200n8 ubi.mtd=rootfs root=mtd:rootfs rootfstype=squashfs rootwait swiotlb=1 && setenv mtdparts mtdparts=nand0:0x3a00000@0x900000(fs)
owrt_setslot1=setenv bootargs console=ttyMSM0,115200n8 ubi.mtd=rootfs_1 root=mtd:rootfs rootfstype=squashfs rootwait swiotlb=1 && setenv mtdparts mtdparts=nand0:0x3a00000@0x4300000(fs)
owrt_slotswap=setexpr owrt_slotactive 1 - \${owrt_slotactive} && saveenv && echo slot swapped. new active slot: \$owrt_slotactive
owrt_slotselect=setenv mtdids nand0=nand0; if test \$owrt_slotactive = 0; then run owrt_setslot0; else run owrt_setslot1; fi
owrt_tftprecover=echo trying to recover firmware with tftp... && sleep 10 && dhcp && flash rootfs && flash rootfs_1 && setenv owrt_bootcount 0 && setenv owrt_slotactive 0 && saveenv && reset
owrt_env_ver=3
bootargs=""
EOF
    fw_setenv --script /tmp/env_tmp
}

sw8_upgrade() {
    local ret val
    CI_ROOTPART="rootfs"

    #get active rootfs part offset
    active_part_name=$(cat /proc/cmdline | grep -o 'ubi.mtd=[^ ]*' | tail -1 | cut -d'=' -f2)
    active_part_dev=$(cat /proc/mtd | grep \"${active_part_name}\" | grep 03a00000 -m 1 | cut -d":" -f 1)
    active_part_offset=$(printf "0x%x\n" $(cat /sys/class/mtd/${active_part_dev}/offset))
    local active=0
    #select partition to install based on active partition offset
    [ -z "$active_part_offset" ] && exit 1
    if [ "$active_part_offset" != "0x900000" ]; then
        active=1
    fi

    val=$(fw_printenv -n owrt_env_ver 2>/dev/null)
    ret=$?
    [ $ret != 0 ] && val=0
    [ $val -lt 3 ] && sw8_env_setup $active
    if [ "$active" = "1" ]; then
        CI_UBIPART="rootfs"
        CI_FWSETENV="owrt_slotactive 0"
    else
        CI_UBIPART="rootfs_1"
        CI_FWSETENV="owrt_slotactive 1"
    fi
    fw_setenv owrt_bootcount 0

    # complete std upgrade
    if nand_upgrade_tar "$1" ; then
        nand_do_upgrade_success
    else
        nand_do_upgrade_failed
    fi
}



qca_do_upgrade() {
	local tar_file="$1"

	local board_dir=$(tar tf $tar_file | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}
	local dev=$(find_mtd_chardev "0:HLOS")

	tar Oxf $tar_file ${board_dir}/kernel | mtd write - ${dev}

	if [ -n "$UPGRADE_BACKUP" ]; then
		tar Oxf $tar_file ${board_dir}/root | mtd -j "$UPGRADE_BACKUP" write - rootfs
	else
		tar Oxf $tar_file ${board_dir}/root | mtd write - rootfs
	fi
}

find_mmc_part() {
	local DEVNAME PARTNAME

	if grep -q "$1" /proc/mtd; then
		echo "" && return 0
	fi

	for DEVNAME in /sys/block/mmcblk*/mmcblk*p*; do
		PARTNAME=$(grep PARTNAME ${DEVNAME}/uevent | cut -f2 -d'=')
		[ "$PARTNAME" = "$1" ] && echo "/dev/$(basename $DEVNAME)" && return 0
	done
}

do_flash_emmc() {
	local tar_file=$1
	local emmcblock=$(find_mmc_part $2)
	local board_dir=$3
	local part=$4

	[ -z "$emmcblock" ] && {
		echo failed to find $2
		return
	}

	echo erase $4
	dd if=/dev/zero of=${emmcblock} 2> /dev/null
	echo flash $4
	tar Oxf $tar_file ${board_dir}/$part | dd of=${emmcblock}
}

emmc_do_upgrade() {
	local tar_file="$1"

	local board_dir=$(tar tf $tar_file | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}
	do_flash_emmc $tar_file '0:HLOS' $board_dir kernel
	do_flash_emmc $tar_file 'rootfs' $board_dir root

	local emmcblock="$(find_mmc_part "rootfs_data")"
	if [ -e "$emmcblock" ]; then
		mkfs.ext4 -F "$emmcblock"
	fi
}

platform_check_image() {
	local magic_long="$(get_magic_long "$1")"
	board=$(board_name)
	case $board in
	cig,wf186w|\
	cig,wf186h|\
	sonicfi,rap630c-311g|\
	sonicfi,rap630w-311g|\
	cybertan,eww631-a1|\
	cybertan,eww631-b1|\
	edgecore,eap104|\
	wallys,dr5018|\
	hfcl,ion4x_w|\
	hfcl,ion4xi_w|\
	optimcloud,d60|\
	optimcloud,d60-5g|\
	optimcloud,d50|\
	optimcloud,d50-5g|\
	yuncore,fap655|\
	glinet,b3000|\
	udaya,a6-id2|\
	edgecore,oap101|\
	edgecore,oap101-6e|\
	edgecore,oap101e|\
	edgecore,oap101e-6e|\
	ikuai,sw8|\
	fplus,wf-ap-624m-iic)
		[ "$magic_long" = "73797375" ] && return 0
		;;
	esac
	return 1
}

platform_do_upgrade() {
	CI_UBIPART="rootfs"
	CI_ROOTPART="ubi_rootfs"
	CI_IPQ807X=1

	board=$(board_name)
	case $board in
	glinet,b3000|\
	edgecore,oap101|\
	edgecore,oap101-6e|\
	edgecore,oap101e|\
	edgecore,oap101e-6e|\
	edgecore,eap104)
		CI_UBIPART="rootfs1"
		[ "$(find_mtd_chardev rootfs)" ] && CI_UBIPART="rootfs"
		nand_upgrade_tar "$1"
		;;
        hfcl,ion4x_w|\
	hfcl,ion4xi_w)
                wp_part=$(fw_printenv primary | cut  -d = -f2)
                echo "Current Primary is $wp_part"
                if [[ $wp_part == 1 ]]; then
                        CI_UBIPART="rootfs"
                        CI_FWSETENV="primary 0"
                else
                        CI_UBIPART="rootfs_1"
                        CI_FWSETENV="primary 1"
                fi
                nand_upgrade_tar "$1"
                ;;
	cig,wf186w|\
	cig,wf186h|\
	udaya,a6-id2|\
	wallys,dr5018|\
	optimcloud,d60|\
	optimcloud,d60-5g|\
	optimcloud,d50|\
	optimcloud,d50-5g|\
	yuncore,fap655)
		[ -f /proc/boot_info/rootfs/upgradepartition ] && {
			CI_UBIPART="$(cat /proc/boot_info/rootfs/upgradepartition)"
			CI_BOOTCFG=1
		}
		nand_upgrade_tar "$1"
		;;
	ikuai,sw8|\
	fplus,wf-ap-624m-iic)
		CI_ROOTPART="rootfs"
		if $(grep -q ubi.mtd=rootfs_1 /proc/cmdline); then
			CI_UBIPART=rootfs
		else
			CI_UBIPART=rootfs_1
		fi
		sw8_upgrade "$1"
		;;
	sonicfi,rap630c-311g|\
	sonicfi,rap630w-311g|\
	cybertan,eww631-a1|\
	cybertan,eww631-b1)
		boot_part=$(fw_printenv bootfrom | cut  -d = -f2)
		echo "Current bootfrom is $boot_part"
		if [[ $boot_part == 1 ]]; then
			CI_UBIPART="rootfs"
			CI_FWSETENV="bootfrom 0"
		else
			CI_UBIPART="rootfs_1"
			CI_FWSETENV="bootfrom 1"
		fi
		nand_upgrade_tar "$1"
		;;
	esac
}
