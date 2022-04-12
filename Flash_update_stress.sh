#!/bin/bash

LOG_LOOP_TIME=1
LOG_LOOP_SLEEP=1
LOG_FILE="fus_log.txt"

TASK_RETRY=0
MAX_RETRY=1

HELP_WORDS="Try: ./${0} <flash_idx> <stress_loop> <image_path>"
PREFIX_MCTP_CMD="mctp-util"
MAX_UPDATE_SIZE=48
IMG_SIZE=4096

BUS_BMC_BIC="0x03"
MCTP_PLDM="0x01"
BIC_RESET="0x18 0x02"
OEM_1S_PEX_FLASH_READ="0xe0 0x72"
OEM_1S_PEX_FLASH_WRITE="0xe0 0x74"
OEM_1S_PEX_FLASH_ERASE="0xe0 0x75"
IANA="0x15 0xa0 0x00"

get_byte_from_hex() {
	local img_path=$1
	local byte_idx=$2
	local img_size=`du -b $img_path |cut -d $'\t' -f 1`
	if (( $byte_idx -ge $img_size )); then
		echo "wrong"
	fi
	ret=`hd -v -s $byte_idx -n 1 $img_path |head -n 1 |cut -d " " -f 3`
	echo $ret
}

c_get_byte_from_hex() {
	local img_path=$1
	local byte_idx=$2
	
	if [ "$byte_idx" -ge "$IMG_SIZE" ]; then
		echo "<error> byte idx is over length!"
	fi
	ret=`hexdump -v -C -s $byte_idx -n 1 $img_path |head -n 1 |cut -d " " -f 3`
	echo $ret
}

resp_cmd_check() {
	local resp=$1
	local pldm_cc=`echo $resp |cut -d " " -f 7`
	local ipmi_cc=`echo $resp |cut -d " " -f 13`

	if [ "$pldm_cc" != "00" ] || [ "$ipmi_cc" != "00" ]; then
		echo "<error> Bad CC: $pldm_cc(pldm) $ipmi_cc(ipmi)"
		return 1
	else
		return 0
	fi
}

bic_reset () {
	echo "<info> BIC reseting..."
	err_flag="BIC_RESET"
	ret=`${PREFIX_MCTP_CMD} 3 0x40 0x0a 0x01 0x80 0x3f 0x01 $IANA $BIC_RESET`
	resp_cmd_check "$ret"
	if (( $? == 1 )); then
		echo "<error> BIC reset error, stop script!"
		exit 0
	fi
	echo "<info> Sleep for 5 sec..."
	sleep 5
	if (( "$TASK_RETRY" -eq "$MAX_RETRY" )); then
		echo "<error> Task retry over limit!" >> $LOG_FILE
		echo "<error> Task retry over limit!"
		echo "<info> Restart mctpd service"
		sv start mctpd_3

		echo ""
		echo "<<< TASK end >>>"
		exit 0
	fi
	let TASK_RETRY+=1
	echo "<info> BIC reseting and retry in $TASK_RETRY/$MAX_RETRY" >> $LOG_FILE
	main_task
}

ending_step() {
	local err_step=$1
	end=$(date +%s)
	
	echo "task timming: $(($end-$start)) sec with error step [$err_step]" >> $LOG_FILE
	if [ "$err_step" != "" ]; then
		echo "<info> Get error in step[$err_step]"
		bic_reset
	fi

	echo "<info> Restart mctpd service"
	sv start mctpd_3

	echo ""
	echo "<<< TASK end >>>"
	exit 0
}

main_task () {
	echo "<<< TASK start >>>"
	start=$(date +%s)

	echo "<info> Stop mctpd service"
	sv stop mctpd_3

	loopTime=1
	end_flag=0
	err_flag="none"
	while (( 1 )); do
		if (( $loopTime > LOG_LOOP_TIME )); then
			echo "Task finish!"
			break
		fi
		echo
		echo "loop[ $loopTime ] - stress task start..."

		# STEP1. Erase
		echo "erasing flash..."
		err_flag="ERASE"
		
		ret=`${PREFIX_MCTP_CMD} 3 0x40 0x0a 0x01 0x80 0x3f 0x01 $IANA $OEM_1S_PEX_FLASH_ERASE $IANA 0x$FLASH_IDX 0x00 0x00`
		resp_cmd_check "$ret"
		if (( $? == 1 )); then
			ending_step $err_flag
		fi
		
		# STEP2. Write
		echo "writing flash..."
		offset=0
		len=$MAX_UPDATE_SIZE
		err_flag="WRITE"
		while (( 1 )); do
			if [ "$(( offset + MAX_UPDATE_SIZE ))" -gt "$IMG_SIZE" ]; then
				len=$(( IMG_SIZE - offset ))
			fi

			# get bytes from image
			data=""
			for (( i=$offset; i<($offset+$len); i++ )); do
				a=$(c_get_byte_from_hex $IMAGE_PATH $i)
				data+="0x$a "
			done

			hex_offset=`printf '%x\n' $offset`
			hex_offset_len=${#hex_offset}
			hex_len=`printf '%x\n' $len`
			echo "   wr: offset 0x$hex_offset len 0x${hex_len}"
			#echo "       data $data"

			# Only support 2 bytes offset
			if (( $hex_offset_len > 4 )); then
				echo "<error> This script only support 2-byte offset update!"
				end_flag=1;
			fi
			
			while (( $hex_offset_len != 4 )); do
				hex_offset="0$hex_offset"
				let hex_offset_len+=1
			done

			offset_0=`echo $hex_offset | cut -c 3-4`
			offset_1=`echo $hex_offset | cut -c 1-2`
			
			#echo "$PREFIX_MCTP_CMD 3 0x40 0x0a 0x01 0x80 0x3f 0x01 $IANA $OEM_1S_PEX_FLASH_WRITE $IANA 0x$FLASH_IDX 0x$offset_0 0x$offset_1 $data"
			ret=`$PREFIX_MCTP_CMD 3 0x40 0x0a 0x01 0x80 0x3f 0x01 $IANA $OEM_1S_PEX_FLASH_WRITE $IANA 0x$FLASH_IDX 0x$offset_0 0x$offset_1 $data`
			resp_cmd_check "$ret"
			if (( $? == 1 )); then
				ending_step $err_flag
			fi

			let offset+=len

			if [ "$offset" -ge "$IMG_SIZE" ]; then
				break;
			fi
		done

		# STEP3. Varify
		echo "verifying flash..."
		offset=0
		len=$MAX_UPDATE_SIZE
		err_flag="VERIFY"
		while (( 1 )); do
			if [ "$(( offset + MAX_UPDATE_SIZE ))" -gt "$IMG_SIZE" ]; then
				len=$(( IMG_SIZE - offset ))
			fi

			# get bytes from image
			data=""
			for (( i=$offset; i<($offset+$len); i++ )); do
				a=$(c_get_byte_from_hex $IMAGE_PATH $i)
				data+="$a"
			done

			hex_offset=`printf '%x\n' $offset`
			hex_offset_len=${#hex_offset}
			hex_len=`printf '%x\n' $len`
			echo "   rd: offset 0x$hex_offset len 0x${hex_len}"
			#echo "       data $data"

			while (( $hex_offset_len != 4 )); do
				hex_offset="0$hex_offset"
				let hex_offset_len+=1
			done

			offset_0=`echo $hex_offset | cut -c 3-4`
			offset_1=`echo $hex_offset | cut -c 1-2`

			ret=`$PREFIX_MCTP_CMD 3 0x40 0x0a 0x01 0x80 0x3f 0x01 $IANA $OEM_1S_PEX_FLASH_READ $IANA 0x$FLASH_IDX 0x$offset_0 0x$offset_1 0x$hex_len`
			resp_cmd_check "$ret"
			if (( $? == 1 )); then
				ending_step $err_flag
			fi
			#echo "$ret | cut -d " " -f 17-$((17+MAX_UPDATE_SIZE))"
			rsp_data=`echo $ret | cut -d " " -f 17-$((17+MAX_UPDATE_SIZE)) | sed 's/ //g'`
			if [ "$rsp_data" != "$data" ]; then
				echo "<error> Verify failed!"
				echo "        img: $data"
				echo "        rsp: $rsp_data"
				ending_step $err_flag
			fi

			let offset+=len

			if [ "$offset" -ge "$IMG_SIZE" ]; then
				break;
			fi
		done
		
		let loopTime+=1
		sleep "$LOG_LOOP_SLEEP"	
	done
}

# MAIN FUNCTION HERE
if (("$#" != 3)); then
	echo $HELP_WORDS
	exit 0
fi

FLASH_IDX=$1
LOG_LOOP_TIME=$2
IMAGE_PATH=$3

if [ ! -f "$IMAGE_PATH" ]; then
    echo "<error> $IMAGE_PATH not exists!"
	echo $HELP_WORDS
	exit 0
fi

img_size=`ls -l $IMAGE_PATH | awk '{print $5}'`
#img_size=`du $IMAGE_PATH |cut -d $'\t' -f 1`
#img_size=`echo $((img_size * 1024))`

if [ "$img_size" -ne "$IMG_SIZE" ]; then
	echo "<error> Update image should only with size 4k!"
	exit 0
fi

echo "<info> Using $IMAGE_PATH as update image."
echo ""

main_task

ending_step
