. /lib/functions/system.sh

RAMFS_COPY_BIN='fw_setenv'
RAMFS_COPY_DATA='/etc/fw_env.config /var/lock/fw_printenv.lock /tmp/downgrade'


#redefine fixed find_mtd_index (show only first found line)
find_mtd_index() {
	local PART="$(grep -m 1 "\"$1\"" /proc/mtd | awk -F: '{print $1}')"
	local INDEX="${PART##mtd}"
	echo ${INDEX}
}


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

sw8v2_env_setup() {
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
owrt_setslot0=setenv bootargs console=ttyMSM0,115200n8 ubi.mtd=rootfs root=mtd:rootfs rootfstype=squashfs rootwait swiotlb=1 && setenv mtdparts mtdparts=nand0:0x3e00000@0x80000(fs)
owrt_setslot1=setenv bootargs console=ttyMSM0,115200n8 ubi.mtd=rootfs_1 root=mtd:rootfs rootfstype=squashfs rootwait swiotlb=1 && setenv mtdparts mtdparts=nand0:0x3e00000@0x0x3e80000(fs)
owrt_slotswap=setexpr owrt_slotactive 1 - \${owrt_slotactive} && saveenv && echo slot swapped. new active slot: \$owrt_slotactive
owrt_slotselect=setenv mtdids nand0=nand0; if test \$owrt_slotactive = 0; then run owrt_setslot0; else run owrt_setslot1; fi
owrt_tftprecover=echo trying to recover firmware with tftp... && sleep 10 && dhcp && flash rootfs && flash rootfs_1 && setenv owrt_bootcount 0 && setenv owrt_slotactive 0 && saveenv && reset
owrt_env_ver=4
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

sw8v2_upgrade() {
	local ret val
	CI_ROOTPART="rootfs"

	#get active rootfs part offset	
	active_part_name=$(cat /proc/cmdline | grep -o 'ubi.mtd=[^ ]*' | tail -1 | cut -d'=' -f2)
	active_part_dev=$(cat /proc/mtd | grep \"${active_part_name}\" | grep 03e00000 -m 1 | cut -d":" -f 1)
	active_part_offset=$(printf "0x%x\n" $(cat /sys/class/mtd/${active_part_dev}/offset))
	local active=0
	#select partition to install based on active partition offset
	[ -z "$active_part_offset" ] && exit 1
	if [ "$active_part_offset" != "0x80000" ]; then
		active=1
	fi

	val=$(fw_printenv -n owrt_env_ver 2>/dev/null)
	ret=$?
	[ $ret != 0 ] && val=0
	[ $val -lt 4 ] && sw8v2_env_setup $active
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

	[ -b "$emmcblock" ] || emmcblock=$(find_mmc_part $2)

	[ -z "$emmcblock" ] && {
		echo failed to find $2
		return
	}

	echo erase $4 / $emmcblock
	dd if=/dev/zero of=${emmcblock} 2> /dev/null
	echo flash $4
	tar Oxf $tar_file ${board_dir}/$part | dd of=${emmcblock}
}

spi_nor_emmc_do_upgrade_bootconfig() {
	local tar_file="$1"

	local board_dir=$(tar tf $tar_file | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}
	[ -f /proc/boot_info/getbinary_bootconfig ] || {
		echo "bootconfig does not exist"
		exit
	}
	CI_ROOTPART="$(cat /proc/boot_info/rootfs/upgradepartition)"
	CI_KERNPART="$(cat /proc/boot_info/0:HLOS/upgradepartition)"

	[ -n "$CI_KERNPART" -a -n "$CI_ROOTPART" ] || {
		echo "kernel or rootfs partition is unknown"
		exit
	}

	local primary="0"
	[ "$(cat /proc/boot_info/rootfs/primaryboot)" = "0" ] && primary="1"
	echo "$primary" > /proc/boot_info/rootfs/primaryboot 2>/dev/null
	echo "$primary" > /proc/boot_info/0:HLOS/primaryboot 2>/dev/null
	cp /proc/boot_info/getbinary_bootconfig /tmp/bootconfig

	do_flash_emmc $tar_file $CI_KERNPART $board_dir kernel
	do_flash_emmc $tar_file $CI_ROOTPART $board_dir root

	local emmcblock="$(find_mmc_part "rootfs_data")"
	if [ -e "$emmcblock" ]; then
		mkfs.ext4 -F "$emmcblock"
	fi

	for part in "0:BOOTCONFIG" "0:BOOTCONFIG1"; do
               local mtdchar=$(echo $(find_mtd_chardev $part) | sed 's/^.\{5\}//')
               if [ -n "$mtdchar" ]; then
                       echo start to update $mtdchar
                       mtd -qq write /proc/boot_info/getbinary_bootconfig "/dev/${mtdchar}" 2>/dev/null && echo update mtd $mtdchar
               else
                       emmcblock=$(find_mmc_part $part)
                       echo erase ${emmcblock}
                       dd if=/dev/zero of=${emmcblock} 2> /dev/null
                       echo update $emmcblock
                       dd if=/tmp/bootconfig of=${emmcblock} 2> /dev/null
               fi
	done
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
	cig,wf188|\
	cig,wf660a|\
	cig,wf188n|\
	cig,wf194c|\
	cig,wf194c4|\
	cig,wf196|\
	cybertan,eww622-a1|\
	cybertan,eww631-a1|\
	cybertan,eww631-b1|\
	glinet,ax1800|\
	glinet,axt1800|\
	indio,um-310ax-v1|\
	indio,um-510axp-v1|\
	indio,um-510axm-v1|\
	wallys,dr5018|\
	wallys,dr6018|\
	wallys,dr6018-v4|\
	edgecore,eap101|\
	edgecore,eap102|\
	edgecore,oap102|\
	edgecore,eap104|\
	liteon,wpx8324|\
	edgecore,eap106|\
	hfcl,ion4xi|\
	hfcl,ion4xi_w|\
	hfcl,ion4x_w|\
	hfcl,ion4xi_HMR|\
	hfcl,ion4xi_wp|\
	hfcl,ion4x|\
	hfcl,ion4x_2|\
	hfcl,ion4xe|\
	muxi,ap3220l|\
	plasmacloud,pax1800-v1|\
	plasmacloud,pax1800-v2|\
	tplink,ex227|\
	tplink,ex447|\
	yuncore,ax840|\
	yuncore,fap650|\
	yuncore,fap655|\
	motorola,q14|\
	muxi,ap3220l|\
	qcom,ipq6018-cp01|\
	qcom,ipq807x-hk01|\
	qcom,ipq807x-hk14|\
   	optimcloud,d60|\
 	optimcloud,d60-5g|\
 	optimcloud,d50|\
 	optimcloud,d50-5g|\
 	ikuai,sw8|\
 	ikuai,sw8v2|\
	fplus,wf-ap-624m-iic|\
	qcom,ipq5018-mp03.3)
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
	cig,wf188)
		qca_do_upgrade $1
		;;
	cig,wf660a)
		spi_nor_emmc_do_upgrade_bootconfig $1
		;;
	motorola,q14)
		emmc_do_upgrade $1
		;;
	cig,wf188n|\
	cig,wf194c|\
	cig,wf194c4|\
	cig,wf196|\
	cybertan,eww622-a1|\
	glinet,ax1800|\
	glinet,axt1800|\
	indio,um-310ax-v1|\
	indio,um-510axp-v1|\
	indio,um-510axm-v1|\
	qcom,ipq6018-cp01|\
	qcom,ipq807x-hk01|\
	qcom,ipq807x-hk14|\
	optimcloud,d60|\
 	optimcloud,d60-5g|\
 	optimcloud,d50|\
 	optimcloud,d50-5g|\
	qcom,ipq5018-mp03.3|\
	wallys,dr5018|\
	wallys,dr6018|\
	wallys,dr6018-v4|\
	yuncore,fap650|\
	tplink,ex447|\
	tplink,ex227|\
	meshpp,s618-cp03|\
	meshpp,s618-cp01)
		nand_upgrade_tar "$1"
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
	hfcl,ion4xi_w|\
	hfcl,ion4x_w|\
	hfcl,ion4xi_HMR|\
	hfcl,ion4xi_wp)
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
	ikuai,sw8v2)
		CI_ROOTPART="rootfs"	
		if $(grep -q ubi.mtd=rootfs_1 /proc/cmdline); then
			CI_UBIPART=rootfs 
		else
			CI_UBIPART=rootfs_1
		fi
		sw8v2_upgrade "$1"
		;;	
	edgecore,eap104|\
	liteon,wpx8324|\
	edgecore,eap106)
		CI_UBIPART="rootfs1"
		[ "$(find_mtd_chardev rootfs)" ] && CI_UBIPART="rootfs"
		nand_upgrade_tar "$1"
		;;
	edgecore,eap101|\
	edgecore,eap102|\
	edgecore,oap102)
		if [ "$(find_mtd_chardev rootfs)" ]; then
			CI_UBIPART="rootfs"
		else
			if [ -e /tmp/downgrade ]; then
				CI_UBIPART="rootfs1"
				fw_setenv active 1 || exit 1
				fw_setenv upgrade_available 0 || exit 1
			elif grep -q rootfs1 /proc/cmdline; then
				CI_UBIPART="rootfs2"
				CI_FWSETENV="active 2"
			else
				CI_UBIPART="rootfs1"
				CI_FWSETENV="active 1"
			fi
		fi
		nand_upgrade_tar "$1"
		;;
	plasmacloud,pax1800-v1|\
	plasmacloud,pax1800-v2)
		PART_NAME="inactive"
		platform_do_upgrade_dualboot_datachk "$1"
		;;
	cig,wf186w|\
	cig,wf186h|\
	yuncore,ax840|\
	yuncore,fap655)
		[ -f /proc/boot_info/rootfs/upgradepartition ] && {
			CI_UBIPART="$(cat /proc/boot_info/rootfs/upgradepartition)"
			CI_BOOTCFG=1
		}
		nand_upgrade_tar "$1"
		;;
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
