#!/bin/bash

# === ПРОВЕРКА ОКРУЖЕНИЯ ДЛЯ БЭКАПОВ ===

echo "=== ПРОВЕРКА ПЕРЕМЕННЫХ ОКРУЖЕНИЯ ==="

# Проверка S3 переменных
echo ""
echo "S3 Credentials:"
if [ -n "$AWS_ACCESS_KEY_ID" ]; then
    echo "  ✅ AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:8}***"
else
    echo "  ❌ AWS_ACCESS_KEY_ID не установлен"
    echo "     Добавьте в ~/.bashrc: export AWS_ACCESS_KEY_ID=\"your_key\""
fi

if [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "  ✅ AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:0:8}***"
else
    echo "  ❌ AWS_SECRET_ACCESS_KEY не установлен"
    echo "     Добавьте в ~/.bashrc: export AWS_SECRET_ACCESS_KEY=\"your_secret\""
fi

# Проверка SSH ключей
echo ""
echo "SSH Keys:"
for key in "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" "$HOME/.ssh/backup_key"; do
    if [ -f "$key" ]; then
        echo "  ✅ $(basename "$key"): $key"
    fi
done

# Проверка зависимостей
echo ""
echo "Зависимости:"
for cmd in jq rustic ssh sshpass; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "  ✅ $cmd: $(which "$cmd")"
    else
        echo "  ❌ $cmd: не установлен"
    fi
done

echo ""
echo "Для установки недостающих зависимостей:"
echo "  sudo apt install jq sshpass"
