. /lib/functions/system.sh

RAMFS_COPY_BIN='fw_printenv fw_setenv'
RAMFS_COPY_DATA='/etc/fw_env.config /var/lock/fw_printenv.lock'

ax840_env_setup() {
	local ubifile=$(board_name)
	local active=$(fw_printenv -n owrt_slotactive)
	[ -z "$active" ] && active=$(hexdump -s 0x94 -n 4 -e '4 "%d"' /dev/mtd$(find_mtd_index 0:bootconfig))
	cat > /tmp/env_tmp << EOF
owrt_slotactive=${active}
owrt_bootcount=0
bootfile=${ubifile}.ubi
owrt_bootcountcheck=if test \$owrt_bootcount > 4; then run owrt_tftprecover; fi; if test \$owrt_bootcount = 3; then run owrt_slotswap; else echo bootcountcheck successfull; fi
owrt_bootinc=if test \$owrt_bootcount < 5; then echo save env part; setexpr owrt_bootcount \${owrt_bootcount} + 1 && saveenv; else echo save env skipped; fi; echo current bootcount: \$owrt_bootcount
bootcmd=run owrt_bootinc && run owrt_bootcountcheck && run owrt_slotselect && run owrt_bootlinux
owrt_bootlinux=echo booting linux... && ubi part fs && ubi read 0x44000000 kernel && bootm; reset
owrt_setslot0=setenv bootargs console=ttyMSM0,115200n8 ubi.mtd=rootfs rootfstype=squashfs && setenv mtdparts mtdparts=nand0:0x3c00000@0(fs)
owrt_setslot1=setenv bootargs console=ttyMSM0,115200n8 ubi.mtd=rootfs_1 rootfstype=squashfs && setenv mtdparts mtdparts=nand0:0x3c00000@0x3c00000(fs)
owrt_slotswap=setexpr owrt_slotactive 1 - \${owrt_slotactive} && saveenv && echo slot swapped. new active slot: \$owrt_slotactive
owrt_slotselect=setenv mtdids nand0=nand0,nand1=spi0.0; if test \$owrt_slotactive = 0; then run owrt_setslot0; else run owrt_setslot1; fi
owrt_tftprecover=echo trying to recover firmware with tftp... && sleep 10 && dhcp && flash rootfs && flash rootfs_1 && setenv owrt_bootcount 0 && setenv owrt_slotactive 0 && saveenv && reset
owrt_env_ver=9
EOF
	fw_setenv --script /tmp/env_tmp
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
	dd if=/dev/zero of=${emmcblock}
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
                mkfs.ext4 "$emmcblock"
        fi
}

platform_check_image() {
	local magic_long="$(get_magic_long "$1")"
	board=$(board_name)
	case $board in
	cig,wf188n|\
	cig,wf194c4|\
	cig,wf196|\
	glinet,ax1800|\
	glinet,axt1800|\
	wallys,dr6018|\
	wallys,dr6018-v4|\
	edgecore,eap101|\
	hfcl,ion4xi|\
	hfcl,ion4x|\
	hfcl,ion4x_2|\
	hfcl,ion4xe|\
	yuncore,ax840|\
	yuncore,fap650)
		[ "$magic_long" = "73797375" ] && return 0
		;;
	esac
	return 1
}

platform_do_upgrade() {
	CI_UBIPART="rootfs"
	CI_ROOTPART="rootfs"
	CI_IPQ807X=1

	board=$(board_name)
	case $board in
	cig,wf188n|\
	glinet,ax1800|\
	glinet,axt1800|\
	wallys,dr6018|\
	wallys,dr6018-v4|\
	yuncore,ax840|\
	yuncore,fap650)
		[ "$(fw_printenv -n owrt_env_ver 2>/dev/null)" -lt 8 ] && ax840_env_setup
		local active="$(fw_printenv -n owrt_slotactive 2>/dev/null)"
		CI_ROOTPART="rootfs"
		if [ "$active" = "1" ]; then
			CI_UBIPART="rootfs"
			CI_FWSETENV="owrt_slotactive 0"
		else
			CI_UBIPART="rootfs_1"
			CI_FWSETENV="owrt_slotactive 1"
		fi
		fw_setenv owrt_bootcount 0
		nand_do_upgrade "$1"
		;;
	hfcl,ion4xi|\
	hfcl,ion4x|\
	hfcl,ion4x_2|\
	hfcl,ion4xe)
		if grep -q rootfs_1 /proc/cmdline; then
			CI_UBIPART="rootfs"
			fw_setenv primary 0 || exit 1
		else
			CI_UBIPART="rootfs_1"
			fw_setenv primary 1 || exit 1
		fi
		nand_upgrade_tar "$1"
		;;
	edgecore,eap101)
		if [ "$(find_mtd_chardev rootfs)" ]; then
			CI_UBIPART="rootfs"
		else
			if grep -q rootfs1 /proc/cmdline; then
				CI_UBIPART="rootfs2"
				CI_FWSETENV="active 2"
			else
				CI_UBIPART="rootfs1"
				CI_FWSETENV="active 1"
			fi
		fi
		nand_upgrade_tar "$1"
		;;
	esac
}
