#!/bin/bash

# === БЫСТРЫЕ КОМАНДЫ ДЛЯ SYSTEMD ===

SERVICE_NAME="rustic-backup"

case "${1:-help}" in
    "start")
        echo "🚀 Запуск бэкапа..."
        systemctl --user start "${SERVICE_NAME}.service"
        ;;
    "status")
        systemctl --user status "${SERVICE_NAME}.service" "${SERVICE_NAME}.timer"
        ;;
    "logs")
        journalctl --user -u "${SERVICE_NAME}.service" -f
        ;;
    "next")
        echo "⏰ Следующие запуски:"
        systemctl --user list-timers "${SERVICE_NAME}.timer"
        ;;
    "enable")
        systemctl --user enable --now "${SERVICE_NAME}.timer"
        echo "✅ Автозапуск включен"
        ;;
    "disable")
        systemctl --user disable --now "${SERVICE_NAME}.timer"
        echo "❌ Автозапуск отключен"
        ;;
    "restart")
        systemctl --user restart "${SERVICE_NAME}.timer"
        echo "🔄 Timer перезапущен"
        ;;
    *)
        echo "Использование: $0 {start|status|logs|next|enable|disable|restart}"
        echo ""
        echo "Команды:"
        echo "  start   - запустить бэкап сейчас"
        echo "  status  - показать статус сервиса и timer'а"
        echo "  logs    - показать логи (Ctrl+C для выхода)"
        echo "  next    - когда следующий запуск"
        echo "  enable  - включить автозапуск"
        echo "  disable - отключить автозапуск"
        echo "  restart - перезапустить timer"
        ;;
esac
