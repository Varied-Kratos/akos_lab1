#!/bin/bash

VIRTUAL_DISK_NAME="virtual_disk"
DISK_SIZE="2048M"   
LOG_DIR_NAME="log"
BACKUP_DIR_NAME="backup"

OS_TYPE=$(uname -s)

if [ "$OS_TYPE" = "Darwin" ]; then
    if mount | grep -q "/Volumes/$VIRTUAL_DISK_NAME"; then
        hdiutil detach "/Volumes/$VIRTUAL_DISK_NAME" -force
    fi
    rm -f "${VIRTUAL_DISK_NAME}.dmg"
fi

if [ "$OS_TYPE" = "Linux" ]; then
    MOUNT_POINT="/mnt/$VIRTUAL_DISK_NAME"
    dd if=/dev/zero of=${VIRTUAL_DISK_NAME}.img bs=$DISK_SIZE count=1
    mkfs.ext4 ${VIRTUAL_DISK_NAME}.img >/dev/null 2>&1
    sudo mkdir -p $MOUNT_POINT
    sudo mount -o loop ${VIRTUAL_DISK_NAME}.img $MOUNT_POINT
    sudo chmod 777 $MOUNT_POINT
    echo "Linux: виртуальный диск смонтирован в $MOUNT_POINT"

elif [ "$OS_TYPE" = "Darwin" ]; then
    MOUNT_POINT="/Volumes/$VIRTUAL_DISK_NAME"
    hdiutil create -size $DISK_SIZE -fs HFS+ -volname $VIRTUAL_DISK_NAME ${VIRTUAL_DISK_NAME}.dmg >/dev/null 2>&1
    hdiutil attach ${VIRTUAL_DISK_NAME}.dmg -mountpoint $MOUNT_POINT >/dev/null 2>&1
    echo "macOS: виртуальный диск смонтирован в $MOUNT_POINT"

else
    echo "Неизвестная ОС: $OS_TYPE"
    exit 1
fi

LOG_DIR="$MOUNT_POINT/$LOG_DIR_NAME"
BACKUP_DIR="$MOUNT_POINT/$BACKUP_DIR_NAME"
mkdir -p "$LOG_DIR" "$BACKUP_DIR"

echo "Созданы папки:"
echo "  LOG: $LOG_DIR"
echo "  BACKUP: $BACKUP_DIR"

create_test_files() {
    local size_mb=$1
    local file_count=$2
    local prefix=$3
    
    echo "Создание $file_count файлов общим размером ${size_mb}MB..."
    
    local file_size=$((size_mb / file_count))
    for i in $(seq 1 $file_count); do
        if [ "$file_size" -gt 0 ]; then
            dd if=/dev/urandom of="$LOG_DIR/${prefix}_file_$i.log" bs=1M count=$file_size status=none
        else
            dd if=/dev/urandom of="$LOG_DIR/${prefix}_file_$i.log" bs=1K count=$((size_mb * 1024 / file_count)) status=none
        fi
        sleep 1
    done
    
    local actual_size=$(du -sm "$LOG_DIR" 2>/dev/null | cut -f1 || echo 0)
    echo "Фактический размер папки log: ${actual_size}MB"
}

cleanup_test() {
    rm -rf "$LOG_DIR"/* "$BACKUP_DIR"/* 2>/dev/null
    echo "Тестовые данные очищены"
}

check_test_result() {
    local test_name=$1
    local expected_condition=$2
    local actual_value=$3
    
    if eval "$expected_condition"; then
        echo "Тест пройден: $test_name"
        return 0
    else
        echo "Тест не пройден: $test_name"
        echo "   Ожидалось: $expected_condition"
        echo "   Получено: $actual_value"
        return 1
    fi
}

run_script_with_yes() {
    local path=$1
    local threshold=$2
    echo "y" | ./script.sh "$path" "$threshold"
}

run_tests() {
    local tests_passed=0
    local total_tests=9
    
    echo "=================== ЗАПУСК ТЕСТОВ ==================="

    echo "ТЕСТ 1: Базовая функциональность"
    echo "ЦЕЛЬ: Проверить основную работу скрипта при превышении порога"
    echo "------------------------------------------------------"
    cleanup_test
    create_test_files 1500 10 "test1"
    
    run_script_with_yes "$LOG_DIR" 70
    
    local remaining_size=$(du -sm "$LOG_DIR" 2>/dev/null | cut -f1 || echo 0)
    local backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
    
    if check_test_result "Базовая функциональность" "[ $backup_count -gt 0 ]" "размер: ${remaining_size}MB, архивов: $backup_count"; then
        ((tests_passed++))
    fi
    echo

    echo "ТЕСТ 2: Порог не превышен"
    echo "ЦЕЛЬ: Проверить что скрипт не архивирует при низкой заполненности"
    echo "------------------------------------------------------"
    cleanup_test
    create_test_files 800 6 "test2"
    
    local backup_count_before=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
    ./script.sh "$LOG_DIR" 70
    local backup_count_after=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
    
    if check_test_result "Порог не превышен" "[ $backup_count_before -eq $backup_count_after ]" "архивов до: $backup_count_before, после: $backup_count_after"; then
        ((tests_passed++))
    fi
    echo

    echo "ТЕСТ 3: Архивация старых файлов"
    echo "ЦЕЛЬ: Проверить приоритет архивации старых файлов"
    echo "------------------------------------------------------"
    cleanup_test
    create_test_files 1700 8 "test3"
    
    oldest_files=$(ls -1 "$LOG_DIR" | head -2)
    echo "Самые старые файлы: $oldest_files"
    
    run_script_with_yes "$LOG_DIR" 70
    
    local missing_count=0
    for file in $oldest_files; do
        if [ ! -f "$LOG_DIR/$file" ]; then
            ((missing_count++))
            echo "  - Файл '$file' заархивирован ✓"
        else
            echo "  - Файл '$file' остался в папке ✗"
        fi
    done
    
    if check_test_result "Архивация старых файлов" "[ $missing_count -gt 0 ]" "заархивировано старых файлов: $missing_count"; then
        ((tests_passed++))
    fi
    echo

    echo "ТЕСТ 4: LZMA сжатие"
    echo "ЦЕЛЬ: Проверить альтернативное сжатие при LAB_MAX_COMPRESSION=1"
    echo "------------------------------------------------------"
    cleanup_test
    create_test_files 1100 6 "test4"
    
    export LAB_MAX_COMPRESSION=1
    run_script_with_yes "$LOG_DIR" 50
    unset LAB_MAX_COMPRESSION
    
    local lzma_archives=$(ls -1 "$BACKUP_DIR"/*.lzma 2>/dev/null | wc -l | tr -d ' ')
    local xz_archives=$(ls -1 "$BACKUP_DIR"/*.xz 2>/dev/null | wc -l | tr -d ' ')
    local total_compressed=$((lzma_archives + xz_archives))
    
    if check_test_result "LZMA сжатие" "[ $total_compressed -gt 0 ]" "найдено LZMA архивов: $total_compressed"; then
        ((tests_passed++))
    fi
    echo

    echo "ТЕСТ 5: Высокое заполнение (85% и более)"
    echo "ЦЕЛЬ: Проверить работу при очень высоком заполнении"
    echo "------------------------------------------------------"
    cleanup_test
    create_test_files 1740 8 "test5"
    
    run_script_with_yes "$LOG_DIR" 70
    
    local backup_count_5=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
    
    if check_test_result "Высокое заполнение" "[ $backup_count_5 -gt 0 ]" "создано архивов: $backup_count_5"; then
        ((tests_passed++))
    fi
    echo

    echo "ТЕСТ 6: Среднее заполнение (65% и более)"
    echo "ЦЕЛЬ: Проверить работу при среднем заполнении"
    echo "------------------------------------------------------"
    cleanup_test
    create_test_files 1330 7 "test6"
    
    run_script_with_yes "$LOG_DIR" 60
    
    local backup_count_6=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
    
    if check_test_result "Среднее заполнение" "[ $backup_count_6 -gt 0 ]" "создано архивов: $backup_count_6"; then
        ((tests_passed++))
    fi
    echo

    echo "ТЕСТ 7: Низкое заполнение(до 59%) с низким порогом(порог 50%)"
    echo "ЦЕЛЬ: Проверить работу при низком заполнении но низком пороге"
    echo "------------------------------------------------------"
    cleanup_test
    create_test_files 1120 5 "test7"
    
    run_script_with_yes "$LOG_DIR" 50
    
    local backup_count_7=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
    
    if check_test_result "Низкое заполнение" "[ $backup_count_7 -gt 0 ]" "создано архивов: $backup_count_7"; then
        ((tests_passed++))
    fi
    echo

    echo "ТЕСТ 8: Много маленьких файлов"
    echo "ЦЕЛЬ: Проверить работу с большим количеством маленьких файлов"
    echo "------------------------------------------------------"
    cleanup_test
    create_test_files 1400 12 "test8"
    
    run_script_with_yes "$LOG_DIR" 65
    
    local backup_count_8=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
    
    if check_test_result "Много маленьких файлов" "[ $backup_count_8 -gt 0 ]" "создано архивов: $backup_count_8"; then
        ((tests_passed++))
    fi
    echo

    echo "ТЕСТ 9: Мало больших файлов"
    echo "ЦЕЛЬ: Проверить работу с малым количеством больших файлов"
    echo "------------------------------------------------------"
    cleanup_test
    create_test_files 1600 4 "test9"
    
    run_script_with_yes "$LOG_DIR" 75
    
    local backup_count_9=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l | tr -d ' ')
    
    if check_test_result "Мало больших файлов" "[ $backup_count_9 -gt 0 ]" "создано архивов: $backup_count_9"; then
        ((tests_passed++))
    fi
    echo

    echo "=================== РЕЗУЛЬТАТЫ ТЕСТИРОВАНИЯ ==================="
    echo "Пройдено тестов: $tests_passed из $total_tests"
    
    if [ "$tests_passed" -eq "$total_tests" ]; then
        echo "Все тесты успешно пройдены."
    else
        echo "Не все тесты пройдены: $tests_passed/$total_tests"
    fi
    
    return $((total_tests - tests_passed))
}

echo "Запуск тестирования..."
echo "Основной скрипт: ./script.sh"
echo "Виртуальный диск: $DISK_SIZE"
echo "Количество тестов: 9"
echo "=========================================================="
run_tests
TEST_RESULT=$?

echo
echo "Очистка виртуального диска..."
if [ "$OS_TYPE" = "Linux" ]; then
    sudo umount $MOUNT_POINT
    sudo rmdir $MOUNT_POINT
    rm -f ${VIRTUAL_DISK_NAME}.img
elif [ "$OS_TYPE" = "Darwin" ]; then
    hdiutil detach $MOUNT_POINT -force >/dev/null 2>&1
    rm -f ${VIRTUAL_DISK_NAME}.dmg
fi

exit $TEST_RESULT