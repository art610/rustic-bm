#!/bin/bash

# === СКАЧИВАТЕЛЬ RUSTIC ===
# Автоматически скачивает установочники rustic для всех платформ

VERSION="v0.9.5"
BASE_URL="https://github.com/rustic-rs/rustic/releases/download/$VERSION"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLERS_DIR="$SCRIPT_DIR/installers1"

echo "🚀 Скачивание Rustic $VERSION для всех платформ..."

mkdir -p "$INSTALLERS_DIR"
cd "$INSTALLERS_DIR"

# Список файлов для скачивания (только tar.gz архивы)
FILES=(
    "rustic-$VERSION-x86_64-unknown-linux-gnu.tar.gz"
    "rustic-$VERSION-aarch64-unknown-linux-gnu.tar.gz"
    "rustic-$VERSION-x86_64-apple-darwin.tar.gz"
    "rustic-$VERSION-aarch64-apple-darwin.tar.gz"
    "rustic-$VERSION-x86_64-pc-windows-msvc.tar.gz"
)

# Функция скачивания
download_file() {
    local url="$1"
    local filename="$2"

    echo "📦 Скачивание $filename..."

    if command -v wget >/dev/null 2>&1; then
        if wget -q --show-progress "$url" -O "$filename"; then
            return 0
        else
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        if curl -L --progress-bar "$url" -o "$filename"; then
            return 0
        else
            return 1
        fi
    else
        echo "❌ Ошибка: нужен wget или curl"
        return 1
    fi
}

# Проверяем, есть ли уже скачанные файлы
echo "🔍 Проверка существующих файлов..."
existing_files=0
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ Уже есть: $file"
        existing_files=$((existing_files + 1))
    fi
done

if [ $existing_files -eq ${#FILES[@]} ]; then
    echo ""
    echo "🎉 Все файлы уже скачаны!"
    read -p "Перескачать заново? (y/N): " redownload
    if [[ ! "$redownload" =~ ^[Yy] ]]; then
        echo "Пропуск скачивания."
        exit 0
    fi
fi

# Скачиваем файлы
echo ""
echo "📥 Начинаем скачивание..."
downloaded_count=0
failed_count=0

for file in "${FILES[@]}"; do
    if download_file "$BASE_URL/$file" "$file"; then
        # Проверяем, что файл действительно скачался и не пустой
        if [ -f "$file" ] && [ -s "$file" ]; then
            echo "✅ Успешно: $file ($(du -h "$file" | cut -f1))"
            downloaded_count=$((downloaded_count + 1))
        else
            echo "❌ Файл пустой или поврежден: $file"
            rm -f "$file"
            failed_count=$((failed_count + 1))
        fi
    else
        echo "❌ Ошибка скачивания: $file"
        failed_count=$((failed_count + 1))
    fi
    echo ""
done

# Итоги
echo "📊 Результаты скачивания:"
echo "   ✅ Успешно: $downloaded_count"
echo "   ❌ Ошибок: $failed_count"
echo "   📁 Всего файлов: ${#FILES[@]}"

if [ $downloaded_count -gt 0 ]; then
    echo ""
    echo "🎉 Скачивание завершено! Файлы в папке installers:"
    ls -lah "$INSTALLERS_DIR"/*.tar.gz 2>/dev/null || echo "Нет файлов .tar.gz"

    echo ""
    echo "📋 Следующие шаги:"
    echo "   1. Подготовить recovery kit: ./prepare_recovery_kit.sh"
    echo "   2. Или установить rustic: ./install_rustic.sh"
else
    echo ""
    echo "❌ Не удалось скачать ни одного файла!"
    echo "Проверьте подключение к интернету и права доступа."
    exit 1
fi

# Дополнительная информация
echo ""
echo "ℹ️  Информация о файлах:"
echo "   • Linux x64:     rustic-$VERSION-x86_64-unknown-linux-gnu.tar.gz"
echo "   • Linux ARM64:   rustic-$VERSION-aarch64-unknown-linux-gnu.tar.gz"
echo "   • macOS Intel:   rustic-$VERSION-x86_64-apple-darwin.tar.gz"
echo "   • macOS Apple:   rustic-$VERSION-aarch64-apple-darwin.tar.gz"
echo "   • Windows:       rustic-$VERSION-x86_64-pc-windows-msvc.tar.gz"
