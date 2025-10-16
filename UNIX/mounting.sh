#!/bin/bash

VIRTUAL_DISK_NAME="virtual_disk"
DISK_SIZE="1024M"   
LOG_DIR_NAME="log"
BACKUP_DIR_NAME="backup"

OS_TYPE=$(uname -s)

if [ "$OS_TYPE" = "Linux" ]; then
    dd if=/dev/zero of=${VIRTUAL_DISK_NAME}.img bs=$DISK_SIZE count=1
    mkfs.ext4 ${VIRTUAL_DISK_NAME}.img
    sudo mkdir -p /mnt/$VIRTUAL_DISK_NAME
    sudo mount -o loop ${VIRTUAL_DISK_NAME}.img /mnt/$VIRTUAL_DISK_NAME


    echo "Linux: виртуальный диск смонтирован в /mnt/$VIRTUAL_DISK_NAME"

elif [ "$OS_TYPE" = "Darwin" ]; then
    hdiutil create -size $DISK_SIZE -fs HFS+ -volname $VIRTUAL_DISK_NAME ${VIRTUAL_DISK_NAME}.dmg
    hdiutil attach ${VIRTUAL_DISK_NAME}.dmg -mountpoint /Volumes/$VIRTUAL_DISK_NAME


    echo "macOS: виртуальный диск смонтирован в /Volumes/$VIRTUAL_DISK_NAME"

else
    echo "Неизвестная ОС: $OS_TYPE"
    exit 1
fi





	
