#!/bin/bash

# === НАСТРОЙКА SYSTEMD ДЛЯ АВТОМАТИЧЕСКОГО БЭКАПА ===

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE="$SCRIPT_DIR/config.json"
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
SERVICE_NAME="rustic-backup"
USER_SYSTEMD_DIR="$HOME/.config/systemd/user"

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_prerequisites() {
    log_info "Проверка предварительных условий..."

    if [ ! -f "$BACKUP_SCRIPT" ]; then
        log_error "Скрипт бэкапа не найден: $BACKUP_SCRIPT"
        return 1
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Файл конфигурации не найден: $CONFIG_FILE"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        log_error "Требуется jq для работы с JSON конфигурацией"
        return 1
    fi

    if ! systemctl --user status >/dev/null 2>&1; then
        log_error "Systemd user manager недоступен"
        log_info "Попробуйте: loginctl enable-linger $USER"
        return 1
    fi

    log_success "Предварительные проверки пройдены"
    return 0
}

load_schedule_config() {
    log_info "Загрузка конфигурации расписания..."

    # Загружаем конфигурацию с раскрытием переменных
    local config_json=$(envsubst < "$CONFIG_FILE")

    # Извлекаем параметры расписания
    SCHEDULE_ENABLED=$(echo "$config_json" | jq -r '.schedule.enabled // true')
    SCHEDULE_PRESET=$(echo "$config_json" | jq -r '.schedule.preset // "daily_morning"')
    CUSTOM_CALENDAR=$(echo "$config_json" | jq -r '.schedule.custom_calendar // ""')
    RANDOMIZED_DELAY=$(echo "$config_json" | jq -r '.schedule.randomized_delay_sec // 900')
    ONLY_AC_POWER=$(echo "$config_json" | jq -r '.schedule.only_on_ac_power // true')
    PERSISTENT=$(echo "$config_json" | jq -r '.schedule.persistent // true')
    WAKE_SYSTEM=$(echo "$config_json" | jq -r '.schedule.wake_system // false')

    # Получаем расписание из пресета или используем custom
    if [ -n "$CUSTOM_CALENDAR" ] && [ "$CUSTOM_CALENDAR" != "null" ]; then
        ON_CALENDAR="$CUSTOM_CALENDAR"
        log_info "Используется пользовательское расписание: $ON_CALENDAR"
    else
        ON_CALENDAR=$(echo "$config_json" | jq -r ".schedule.presets.$SCHEDULE_PRESET // \"*-*-* 02:00:00\"")
        log_info "Используется пресет '$SCHEDULE_PRESET': $ON_CALENDAR"
    fi

    log_success "Конфигурация расписания загружена"
}

show_schedule_config() {
    echo ""
    log_info "=== ТЕКУЩАЯ КОНФИГУРАЦИЯ РАСПИСАНИЯ ==="
    echo "Автозапуск включен: $SCHEDULE_ENABLED"
    echo "Пресет: $SCHEDULE_PRESET"
    echo "Расписание: $ON_CALENDAR"
    echo "Случайная задержка: $RANDOMIZED_DELAY сек"
    echo "Только при питании от сети: $ONLY_AC_POWER"
    echo "Постоянное хранение: $PERSISTENT"
    echo "Пробуждение системы: $WAKE_SYSTEM"
    echo "================================================"
}

create_service_file() {
    local service_file="$USER_SYSTEMD_DIR/${SERVICE_NAME}.service"

    log_info "Создание service файла: $service_file"

    mkdir -p "$USER_SYSTEMD_DIR"

    cat > "$service_file" << EOF
[Unit]
Description=Rustic Backup Service
Documentation=file://$SCRIPT_DIR/README.md
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$USER
Group=$(id -gn)
WorkingDirectory=$SCRIPT_DIR
ExecStart=$BACKUP_SCRIPT backup
Environment=HOME=$HOME
Environment=PATH=$PATH
StandardOutput=journal
StandardError=journal

# Политики перезапуска
Restart=no
RestartSec=300

# Ограничения ресурсов
CPUQuota=50%
MemoryMax=2G
IOWeight=100

# Безопасность
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$SCRIPT_DIR $HOME/.backup_states $HOME/rustic-backup

[Install]
WantedBy=default.target
EOF

    chmod 644 "$service_file"
    log_success "Service файл создан"
}

create_timer_file() {
    local timer_file="$USER_SYSTEMD_DIR/${SERVICE_NAME}.timer"

    log_info "Создание timer файла: $timer_file"

    # Загружаем конфигурацию расписания
    load_schedule_config

    # Проверяем, включено ли расписание
    if [ "$SCHEDULE_ENABLED" != "true" ]; then
        log_warning "Расписание отключено в конфигурации (schedule.enabled = false)"
        log_info "Файл timer будет создан, но не активирован"
    fi

    cat > "$timer_file" << EOF
[Unit]
Description=Timer for Rustic Backup Service
Requires=${SERVICE_NAME}.service

[Timer]
OnCalendar=$ON_CALENDAR
RandomizedDelaySec=$RANDOMIZED_DELAY
Persistent=$PERSISTENT
WakeSystem=$WAKE_SYSTEM

EOF

    # Добавляем условие питания от сети если включено
    if [ "$ONLY_AC_POWER" = "true" ]; then
        cat >> "$timer_file" << EOF
# Запускать только при наличии питания (для ноутбуков)
ConditionACPower=true

EOF
    fi

    cat >> "$timer_file" << EOF
[Install]
WantedBy=timers.target
EOF

    chmod 644 "$timer_file"
    log_success "Timer файл создан"
    show_schedule_config
}

show_available_presets() {
    echo ""
    log_info "=== ДОСТУПНЫЕ ПРЕСЕТЫ РАСПИСАНИЯ ==="

    local config_json=$(envsubst < "$CONFIG_FILE")
    echo "$config_json" | jq -r '.schedule.presets | to_entries[] | "\(.key): \(.value)"' | while IFS=: read -r preset schedule; do
        echo "  $preset: $schedule"
    done
}

edit_schedule_config() {
    log_info "Редактирование конфигурации расписания..."

    show_available_presets

    echo ""
    echo "Выберите действие:"
    echo "1) Изменить пресет"
    echo "2) Задать пользовательское расписание"
    echo "3) Включить/отключить автозапуск"
    echo "4) Изменить настройки"
    echo "0) Отмена"

    read -p "Выберите вариант (0-4): " edit_choice

    case $edit_choice in
        1)
            show_available_presets
            echo ""
            read -p "Введите название пресета: " new_preset

            # Проверяем существование пресета
            local config_json=$(envsubst < "$CONFIG_FILE")
            local preset_exists=$(echo "$config_json" | jq -r ".schedule.presets.$new_preset // \"null\"")

            if [ "$preset_exists" != "null" ]; then
                # Обновляем конфигурацию
                jq ".schedule.preset = \"$new_preset\" | .schedule.custom_calendar = \"\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                log_success "Пресет изменен на: $new_preset"
            else
                log_error "Пресет '$new_preset' не найден"
            fi
            ;;
        2)
            echo ""
            echo "Примеры пользовательских расписаний:"
            echo "  *-*-* 03:30:00           - ежедневно в 03:30"
            echo "  Mon,Wed,Fri *-*-* 12:00  - пн,ср,пт в 12:00"
            echo "  *-*-15 02:00:00          - 15 числа каждого месяца"
            echo ""
            read -p "Введите расписание systemd: " custom_schedule

            if [ -n "$custom_schedule" ]; then
                jq ".schedule.custom_calendar = \"$custom_schedule\"" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                log_success "Пользовательское расписание установлено: $custom_schedule"
            fi
            ;;
        3)
            read -p "Включить автозапуск? (y/N): " enable_auto
            local enabled="false"
            [[ "$enable_auto" =~ ^[Yy] ]] && enabled="true"

            jq ".schedule.enabled = $enabled" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
            log_success "Автозапуск: $enabled"
            ;;
        4)
            echo ""
            read -p "Случайная задержка (сек) [$RANDOMIZED_DELAY]: " new_delay
            read -p "Только при питании от сети? (y/N): " ac_power
            read -p "Постоянное хранение? (y/N): " persistent

            # Обновляем только заданные параметры
            local updates=()
            [ -n "$new_delay" ] && updates+=(".schedule.randomized_delay_sec = $new_delay")
            [[ "$ac_power" =~ ^[Yy] ]] && updates+=(".schedule.only_on_ac_power = true") || updates+=(".schedule.only_on_ac_power = false")
            [[ "$persistent" =~ ^[Yy] ]] && updates+=(".schedule.persistent = true") || updates+=(".schedule.persistent = false")

            if [ ${#updates[@]} -gt 0 ]; then
                local jq_filter=$(IFS=' | '; echo "${updates[*]}")
                jq "$jq_filter" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
                log_success "Настройки обновлены"
            fi
            ;;
        0)
            log_info "Отмена редактирования"
            return
            ;;
        *)
            log_error "Неверный выбор"
            return
            ;;
    esac

    # Пересоздаем timer файл с новой конфигурацией
    create_timer_file

    # Перезагружаем systemd конфигурацию
    systemctl --user daemon-reload

    # Перезапускаем timer если он активен
    if systemctl --user is-active "${SERVICE_NAME}.timer" >/dev/null 2>&1; then
        systemctl --user restart "${SERVICE_NAME}.timer"
        log_success "Timer перезапущен с новой конфигурацией"
    fi
}

install_service() {
    log_info "Установка systemd сервиса..."

    # Перезагружаем systemd конфигурацию
    systemctl --user daemon-reload

    if [ $? -eq 0 ]; then
        log_success "Systemd конфигурация перезагружена"
    else
        log_error "Ошибка перезагрузки systemd конфигурации"
        return 1
    fi

    # Включаем linger для пользователя
    if ! loginctl show-user "$USER" | grep -q "Linger=yes"; then
        log_info "Включение linger для пользователя $USER..."
        sudo loginctl enable-linger "$USER"
    fi

    log_success "Сервис установлен"
}

enable_service() {
    # Загружаем конфигурацию чтобы проверить enabled
    load_schedule_config

    if [ "$SCHEDULE_ENABLED" != "true" ]; then
        log_warning "Автозапуск отключен в конфигурации (schedule.enabled = false)"
        log_info "Включите его в config.json или через редактирование расписания"
        return 1
    fi

    log_info "Включение автоматического запуска..."

    systemctl --user enable "${SERVICE_NAME}.timer"
    systemctl --user start "${SERVICE_NAME}.timer"

    if [ $? -eq 0 ]; then
        log_success "Автоматический запуск включен"
        return 0
    else
        log_error "Ошибка включения автоматического запуска"
        return 1
    fi
}

show_status() {
    echo ""
    log_info "=== СТАТУС СЕРВИСА ==="

    # Показываем конфигурацию расписания
    load_schedule_config
    show_schedule_config

    echo ""
    echo "Service:"
    systemctl --user status "${SERVICE_NAME}.service" --no-pager -l

    echo ""
    echo "Timer:"
    systemctl --user status "${SERVICE_NAME}.timer" --no-pager -l

    echo ""
    echo "Следующие запуски:"
    systemctl --user list-timers "${SERVICE_NAME}.timer" --no-pager

    echo ""
    echo "Последние логи:"
    journalctl --user -u "${SERVICE_NAME}.service" -n 10 --no-pager
}

disable_service() {
    log_info "Отключение автоматического запуска..."

    systemctl --user stop "${SERVICE_NAME}.timer" 2>/dev/null
    systemctl --user disable "${SERVICE_NAME}.timer" 2>/dev/null
    systemctl --user stop "${SERVICE_NAME}.service" 2>/dev/null

    log_success "Автоматический запуск отключен"
}

uninstall_service() {
    log_info "Удаление systemd сервиса..."

    disable_service

    # Удаляем файлы
    rm -f "$USER_SYSTEMD_DIR/${SERVICE_NAME}.service"
    rm -f "$USER_SYSTEMD_DIR/${SERVICE_NAME}.timer"

    # Перезагружаем конфигурацию
    systemctl --user daemon-reload

    log_success "Сервис удален"
}

test_backup() {
    log_info "Тестовый запуск бэкапа..."

    if systemctl --user start "${SERVICE_NAME}.service"; then
        log_success "Тестовый запуск начат"

        echo "Следите за статусом командой:"
        echo "  systemctl --user status ${SERVICE_NAME}.service"
        echo "  journalctl --user -u ${SERVICE_NAME}.service -f"
    else
        log_error "Ошибка тестового запуска"
        return 1
    fi
}

show_menu() {
    echo ""
    echo "=========================================="
    echo "     НАСТРОЙКА SYSTEMD ДЛЯ БЭКАПА"
    echo "=========================================="
    echo "1) Установить и настроить автозапуск"
    echo "2) Показать статус сервиса"
    echo "3) Включить автозапуск"
    echo "4) Отключить автозапуск"
    echo "5) Тестовый запуск бэкапа"
    echo "6) Показать логи"
    echo "7) ⚙️  Редактировать расписание"
    echo "8) 📋 Показать доступные пресеты"
    echo "9) Удалить сервис"
    echo "0) Выход"
    echo "=========================================="
}

show_logs() {
    echo ""
    log_info "=== ЛОГИ СЕРВИСА ==="
    echo "Используйте Ctrl+C для выхода"
    echo ""

    journalctl --user -u "${SERVICE_NAME}.service" -f
}

main() {
    if ! check_prerequisites; then
        exit 1
    fi

    case "${1:-menu}" in
        "install")
            create_service_file
            create_timer_file
            install_service
            enable_service
            show_status
            ;;
        "status")
            show_status
            ;;
        "enable")
            enable_service
            ;;
        "disable")
            disable_service
            ;;
        "test")
            test_backup
            ;;
        "logs")
            show_logs
            ;;
        "schedule")
            edit_schedule_config
            ;;
        "presets")
            show_available_presets
            ;;
        "uninstall")
            read -p "Вы уверены, что хотите удалить сервис? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy] ]]; then
                uninstall_service
            fi
            ;;
        "menu"|"")
            while true; do
                show_menu
                read -p "Выберите действие (0-9): " choice

                case $choice in
                    1)
                        create_service_file
                        create_timer_file
                        install_service
                        enable_service
                        ;;
                    2) show_status ;;
                    3) enable_service ;;
                    4) disable_service ;;
                    5) test_backup ;;
                    6) show_logs ;;
                    7) edit_schedule_config ;;
                    8) show_available_presets ;;
                    9)
                        read -p "Вы уверены? (y/N): " confirm
                        if [[ "$confirm" =~ ^[Yy] ]]; then
                            uninstall_service
                        fi
                        ;;
                    0)
                        log_info "До свидания!"
                        exit 0
                        ;;
                    *) log_error "Неверный выбор" ;;
                esac

                echo ""
                read -p "Нажмите Enter для продолжения..."
            done
            ;;
        *)
            echo "Использование: $0 [install|status|enable|disable|test|logs|schedule|presets|uninstall|menu]"
            exit 1
            ;;
    esac
}

main "$@"
