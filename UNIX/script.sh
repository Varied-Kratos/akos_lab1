#!/bin/bash

path=${1:-$(pwd)}
max_cap=${2:-70}

OS_TYPE=$(uname -s)

while [ ! -d "$path" ]; do
    read -p "Введите правильный путь до папки: " path
    path=${path/#\~/$HOME}
done

while [ "$max_cap" -lt 10 ] || [ "$max_cap" -ge 100 ]; do
    read -p "Введите верный коэффициент заполненности(по умолчанию 70%): " max_cap
    max_cap=${max_cap:-70}
done

cd "$path" || exit 1

backup_dir="$path/../backup"
mkdir -p "$backup_dir"

if [ "$OS_TYPE" = "Darwin" ]; then
    all_files=($(ls -1t | tail -r))
else
    all_files=($(ls -1t | tac))
fi

disk_info=$(df -k "$path" | awk 'NR==2')
total_bytes=$(( $(echo "$disk_info" | awk '{print $2}') * 1024 ))
used_bytes=$(( $(echo "$disk_info" | awk '{print $3}') * 1024 ))
capacity=$(( used_bytes * 100 / total_bytes ))

cur_bytes=$used_bytes
cur_capacity=$capacity

if [ "$capacity" -ge "$max_cap" ]; then
    echo "Папка заполнена на ${capacity}%. Заполнение превышает порог. Создание backup..."
    files_to_delete=()

    for item in "${all_files[@]}"; do
        [ -f "$item" ] || continue
        
        if [ "$OS_TYPE" = "Darwin" ]; then
            size=$(stat -f%z "$item")
        else
            size=$(stat -c%s "$item")
        fi
        
        cur_bytes=$(( cur_bytes - size ))
        new_capacity=$(( cur_bytes * 100 / total_bytes ))

        files_to_delete+=("$item")

        if [ "$new_capacity" -lt "$max_cap" ]; then
            break
        fi
    done

    echo
    echo "Файлы для архивации и удаления:"
    echo "Папка будет заполнена на ${new_capacity}%"
    printf "%s\n" "${files_to_delete[@]}"
    read -p "Хотите продолжить[y/n]: " decision

    if [ "$decision" = "y" ] || [ "$decision" = "Y" ]; then
        timestamp=$(date +%Y%m%d_%H%M%S)
        if [ "$LAB_MAX_COMPRESSION" = "1" ]; then
            archive_base="$backup_dir/backup_$timestamp.tar"
            tar -cf "$archive_base" "${files_to_delete[@]}" 2>/dev/null
            
            if command -v lzma >/dev/null 2>&1; then
                lzma -f "$archive_base"
                archive_path="${archive_base}.lzma"
            else
                xz -f "$archive_base"
                archive_path="${archive_base}.xz"
            fi
            echo "Создан LZMA архив: $archive_path"
        else
            archive_path="$backup_dir/backup_$timestamp.tar.gz"
            tar -czf "$archive_path" "${files_to_delete[@]}" 2>/dev/null
            echo "Создан gzip архив: $archive_path"
        fi
        rm -r "${files_to_delete[@]}"
    fi

else
    echo "Заполненность в норме (${capacity}%)."
fi
