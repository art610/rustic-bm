#!/bin/bash

# === ОБНОВИТЕЛЬ ВЕРСИИ RUSTIC ===
# Позволяет легко изменить версию для скачивания

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOAD_SCRIPT="$SCRIPT_DIR/download_rustic.sh"

echo "🔄 Обновитель версии Rustic"

# Текущая версия
if [ -f "$DOWNLOAD_SCRIPT" ]; then
    current_version=$(grep '^VERSION=' "$DOWNLOAD_SCRIPT" | cut -d'"' -f2)
    echo "📍 Текущая версия: $current_version"
else
    echo "❌ Файл download_rustic.sh не найден!"
    exit 1
fi

echo ""
echo "🌐 Проверяем последнюю версию на GitHub..."

# Получаем последнюю версию с GitHub API
if command -v curl >/dev/null 2>&1; then
    latest_version=$(curl -s https://api.github.com/repos/rustic-rs/rustic/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
elif command -v wget >/dev/null 2>&1; then
    latest_version=$(wget -qO- https://api.github.com/repos/rustic-rs/rustic/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
else
    echo "⚠️  Не удалось проверить последнюю версию (нужен curl или wget)"
    latest_version="неизвестно"
fi

if [ -n "$latest_version" ] && [ "$latest_version" != "неизвестно" ]; then
    echo "🆕 Последняя версия: $latest_version"

    if [ "$current_version" = "$latest_version" ]; then
        echo "✅ У вас уже последняя версия!"
    else
        echo "🔄 Доступно обновление: $current_version → $latest_version"
    fi
else
    echo "⚠️  Не удалось определить последнюю версию"
fi

echo ""
read -p "Введите желаемую версию (например, v0.9.6) или Enter для [$latest_version]: " new_version

if [ -z "$new_version" ]; then
    new_version="$latest_version"
fi

if [ -z "$new_version" ] || [ "$new_version" = "неизвестно" ]; then
    echo "❌ Не указана версия для обновления"
    exit 1
fi

if [ "$new_version" = "$current_version" ]; then
    echo "ℹ️  Версия не изменилась"
    exit 0
fi

# Обновляем скрипт
echo "🔄 Обновление download_rustic.sh с $current_version на $new_version..."

sed -i.bak "s/VERSION=\"$current_version\"/VERSION=\"$new_version\"/g" "$DOWNLOAD_SCRIPT"

if [ $? -eq 0 ]; then
    echo "✅ Версия обновлена успешно!"
    echo ""
    echo "📋 Теперь можете:"
    echo "   1. Скачать новые файлы: ./download_rustic.sh"
    echo "   2. Подготовить recovery kit: ./prepare_recovery_kit.sh"

    # Показываем изменения
    echo ""
    echo "📝 Изменения в download_rustic.sh:"
    echo "   Было: VERSION=\"$current_version\""
    echo "   Стало: VERSION=\"$new_version\""
else
    echo "❌ Ошибка при обновлении файла"
    exit 1
fi
