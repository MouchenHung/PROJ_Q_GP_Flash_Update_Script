#!/bin/bash
LOG_FILE="fus_log.txt"

IMG_1="test_img_1.bin"
IMG_2="test_img_2.bin"
IMG_3="test_img_3.bin"

echo "Start record..." > $LOG_FILE
loop=1
while (( 1 )); do
	echo "========LOOP[$loop]======== IMAGE 1: $IMG_1" >> $LOG_FILE
	echo "========LOOP[$loop]======== IMAGE 1"
	bash Flash_update_stress.sh 0 1 $IMG_1
	echo "========LOOP[$loop]======== IMAGE 2: $IMG_2" >> $LOG_FILE
	echo "========LOOP[$loop]======== IMAGE 2"
	bash Flash_update_stress.sh 0 1 $IMG_2
	echo "========LOOP[$loop]======== IMAGE 3: $IMG_3" >> $LOG_FILE
	echo "========LOOP[$loop]======== IMAGE 3"
	bash Flash_update_stress.sh 0 1 $IMG_3
	let loop+=1
done