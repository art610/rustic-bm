#!/bin/bash

# === ПРОВЕРКА ОКРУЖЕНИЯ ДЛЯ БЭКАПОВ ===

echo "=== ПРОВЕРКА ПЕРЕМЕННЫХ ОКРУЖЕНИЯ ==="

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
