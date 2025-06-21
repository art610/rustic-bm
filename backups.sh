#!/bin/bash

export LANG=C.UTF-8

# --- ОПРЕДЕЛЕНИЕ ПУТЕЙ ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
INSTALLERS_DIR="$SCRIPT_DIR/installers"
CREDENTIALS_DIR="$SCRIPT_DIR/.credentials"

# --- ПРОВЕРКА ЗАВИСИМОСТЕЙ ---
check_dependencies() {
    local missing_deps=()

    # Проверяем jq для работы с JSON
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi

    # Проверяем envsubst
    if ! command -v envsubst >/dev/null 2>&1; then
        missing_deps+=("gettext-base")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "ОШИБКА: Отсутствуют зависимости: ${missing_deps[*]}"
        echo "Установите их командой: sudo apt install ${missing_deps[*]}"
        exit 1
    fi
}

# --- ФУНКЦИИ КОНФИГУРАЦИИ ---
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
{
  "backup": {
    "source_dirs": [
      "$HOME/.config"
    ],
    "primary_repo": "local",
    "state_dir": "$HOME/.backup_states",
    "log_file": "$HOME/backup_manager.log"
  },
  "repositories": {
    "local": {
      "type": "local",
      "enabled": true,
      "path": "$HOME/rustic-backup",
      "description": "Локальное хранилище"
    },
    "s3_aws": {
      "type": "s3",
      "enabled": false,
      "s3_region": "us-east-1",
      "s3_service_name": "s3",
      "s3_endpoint_url": "",
      "s3_bucket": "my-backup-bucket",
      "prefix": "rustic-backups/",
      "description": "AWS S3"
    }
  },
  "multi_repo": {
    "enabled": false,
    "sync_all": true,
    "repositories": ["local"],
    "require_all_success": false,
    "parallel_uploads": false
  },
  "schedule": {
    "enabled": true,
    "preset": "daily_twice",
    "custom_calendar": "",
    "randomized_delay_sec": 900,
    "only_on_ac_power": true,
    "persistent": true,
    "wake_system": false,
    "presets": {
      "hourly": "hourly",
      "every_6h": "*-*-* 00,06,12,18:00:00",
      "daily_morning": "*-*-* 02:00:00",
      "daily_twice": "*-*-* 02,14:00:00",
      "workdays_only": "Mon..Fri *-*-* 02:00:00",
      "business_hours": "Mon..Fri *-*-* 09,11,13,15,17:00:00",
      "weekly": "Mon *-*-* 03:00:00",
      "monthly": "*-*-01 02:00:00"
    }
  },
  "exclude": {
    "patterns": [
      "*.tmp",
      "*.log",
      "*.cache",
      "*.pyc",
      "*.swp",
      "*~",
      "*.bak",
      "*.backup"
    ],
    "directories": [
      ".cache",
      "node_modules",
      ".git/objects",
      "target",
      "__pycache__",
      ".vscode",
      ".idea",
      ".venv",
      "venv",
      "env",
      ".env",
      "build",
      "dist",
      ".next",
      "coverage"
    ],
    "files": [
      ".DS_Store",
      "Thumbs.db",
      "desktop.ini",
      ".gitkeep"
    ]
  },
  "retention": {
    "keep_daily": 7,
    "keep_weekly": 4,
    "keep_monthly": 6,
    "keep_yearly": 2
  },
  "safety": {
    "min_total_dir_size_kb": 2,
    "enable_size_check": true,
    "enable_checksum_verification": true
  },
  "rustic": {
    "compression": "auto",
    "encryption": "repokey",
    "threads": 4
  },
  "notifications": {
    "enable_desktop_notifications": true,
    "email_notifications": false,
    "email_address": ""
  }
}
EOF
    echo "Создан файл конфигурации по умолчанию: $CONFIG_FILE"
    echo "Отредактируйте его под свои нужды перед запуском."
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Файл конфигурации не найден. Создаем конфигурацию по умолчанию..."
        create_default_config
        exit 0
    fi

    # Проверяем валидность JSON
    if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
        echo "ОШИБКА: Некорректный JSON в файле конфигурации: $CONFIG_FILE"
        exit 1
    fi

    # Загружаем конфигурацию с раскрытием переменных окружения
    CONFIG_JSON=$(envsubst < "$CONFIG_FILE")

    # Извлекаем значения
    mapfile -t SOURCE_DIRS < <(echo "$CONFIG_JSON" | jq -r '.backup.source_dirs[]')

    # Проверяем новую структуру с repositories или старую с repo_path
    if echo "$CONFIG_JSON" | jq -e '.repositories' >/dev/null 2>&1; then
        # Новая структура - используем primary_repo
        PRIMARY_REPO=$(echo "$CONFIG_JSON" | jq -r '.backup.primary_repo // "local"')
        RUSTIC_REPO=$(get_repo_url "$PRIMARY_REPO" "$CONFIG_JSON")
    else
        # Старая структура - используем repo_path
        RUSTIC_REPO=$(echo "$CONFIG_JSON" | jq -r '.backup.repo_path')
    fi

    STATE_DIR=$(echo "$CONFIG_JSON" | jq -r '.backup.state_dir')
    LOG_FILE=$(echo "$CONFIG_JSON" | jq -r '.backup.log_file')

    KEEP_DAILY=$(echo "$CONFIG_JSON" | jq -r '.retention.keep_daily')
    KEEP_WEEKLY=$(echo "$CONFIG_JSON" | jq -r '.retention.keep_weekly')
    KEEP_MONTHLY=$(echo "$CONFIG_JSON" | jq -r '.retention.keep_monthly')
    KEEP_YEARLY=$(echo "$CONFIG_JSON" | jq -r '.retention.keep_yearly')

    MIN_TOTAL_DIR_SIZE_KB=$(echo "$CONFIG_JSON" | jq -r '.safety.min_total_dir_size_kb')
    ENABLE_SIZE_CHECK=$(echo "$CONFIG_JSON" | jq -r '.safety.enable_size_check')
    ENABLE_CHECKSUM_VERIFICATION=$(echo "$CONFIG_JSON" | jq -r '.safety.enable_checksum_verification')

    RUSTIC_THREADS=$(echo "$CONFIG_JSON" | jq -r '.rustic.threads')
    RUSTIC_COMPRESSION=$(echo "$CONFIG_JSON" | jq -r '.rustic.compression')
    RUSTIC_ENCRYPTION=$(echo "$CONFIG_JSON" | jq -r '.rustic.encryption // "repokey"')

    PARALLEL_UPLOADS=$(echo "$CONFIG_JSON" | jq -r '.multi_repo.parallel_uploads // false')

    ENABLE_DESKTOP_NOTIFICATIONS=$(echo "$CONFIG_JSON" | jq -r '.notifications.enable_desktop_notifications')

}

validate_config() {
    local errors=0

    echo "🔍 Проверка конфигурации..."

    # Проверяем исходные директории
    for dir in "${SOURCE_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "⚠️  Директория не найдена: $dir"
            errors=$((errors + 1))
        fi
    done

    # Проверяем доступность родительских директорий
    local repo_parent=$(dirname "$RUSTIC_REPO")
    if [ ! -d "$repo_parent" ]; then
        echo "⚠️  Родительская директория репозитория недоступна: $repo_parent"
        errors=$((errors + 1))
    fi

    local state_parent=$(dirname "$STATE_DIR")
    if [ ! -d "$state_parent" ]; then
        echo "⚠️  Родительская директория состояний недоступна: $state_parent"
        errors=$((errors + 1))
    fi

    local log_parent=$(dirname "$LOG_FILE")
    if [ ! -d "$log_parent" ]; then
        echo "⚠️  Родительская директория логов недоступна: $log_parent"
        errors=$((errors + 1))
    fi

    # Проверяем числовые значения
    if ! [[ "$KEEP_DAILY" =~ ^[0-9]+$ ]] || [ "$KEEP_DAILY" -lt 1 ]; then
        echo "❌ Некорректное значение keep_daily: $KEEP_DAILY"
        errors=$((errors + 1))
    fi

    if ! [[ "$RUSTIC_THREADS" =~ ^[0-9]+$ ]] || [ "$RUSTIC_THREADS" -lt 1 ]; then
        echo "❌ Некорректное значение threads: $RUSTIC_THREADS"
        errors=$((errors + 1))
    fi

    if [ $errors -gt 0 ]; then
        echo "❌ Обнаружено $errors ошибок в конфигурации"
        return 1
    else
        echo "✅ Конфигурация корректна"
        return 0
    fi
}

generate_exclude_file() {
    local exclude_file="$SCRIPT_DIR/rustic-exclude.txt"

    # Очищаем файл
    > "$exclude_file"

    # Добавляем паттерны
    echo "$CONFIG_JSON" | jq -r '.exclude.patterns[]' >> "$exclude_file"

    # Добавляем директории с префиксом
    echo "$CONFIG_JSON" | jq -r '.exclude.directories[]' | while read -r dir; do
        echo "*/$dir/*" >> "$exclude_file"
        echo "$dir/*" >> "$exclude_file"
    done

    # Добавляем файлы
    echo "$CONFIG_JSON" | jq -r '.exclude.files[]' | while read -r file; do
        echo "*/$file" >> "$exclude_file"
        echo "$file" >> "$exclude_file"
    done

    echo "$exclude_file"
}

show_config_summary() {
    echo "=== ТЕКУЩАЯ КОНФИГУРАЦИЯ ==="
    echo "Исходные директории: ${#SOURCE_DIRS[@]} штук"
    for dir in "${SOURCE_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "?")
            echo "  ✓ $dir ($size)"
        else
            echo "  ✗ $dir (не найдена)"
        fi
    done
    echo "Репозиторий: $RUSTIC_REPO"
    if [ -d "$RUSTIC_REPO" ]; then
        local repo_size=$(du -sh "$RUSTIC_REPO" 2>/dev/null | cut -f1 || echo "?")
        echo "  Размер репозитория: $repo_size"
    fi
    echo "Хранение: $KEEP_DAILY дней, $KEEP_WEEKLY недель, $KEEP_MONTHLY месяцев, $KEEP_YEARLY лет"
    echo "Потоков: $RUSTIC_THREADS"
    echo "Сжатие: $RUSTIC_COMPRESSION"
    echo "Шифрование: $RUSTIC_ENCRYPTION"

    # Показываем мульти-репозиторий настройки если используется новая структура
    if echo "$CONFIG_JSON" | jq -e '.repositories' >/dev/null 2>&1; then
        echo "Мульти-репозиторий: $MULTI_REPO_ENABLED"
        if [ "$MULTI_REPO_ENABLED" = "true" ]; then
            echo "  Параллельные загрузки: $PARALLEL_UPLOADS"
            echo "  Требовать успех всех: $REQUIRE_ALL_SUCCESS"
        fi
    fi
    echo "================================"
}

# --- НОВЫЕ ФУНКЦИИ ДЛЯ РАБОТЫ С РЕПОЗИТОРИЯМИ ---

# Функции проверки переменных окружения
check_s3_environment() {
    local missing_vars=()

    if [ -z "$AWS_ACCESS_KEY_ID" ]; then
        missing_vars+=("AWS_ACCESS_KEY_ID")
    fi

    if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        missing_vars+=("AWS_SECRET_ACCESS_KEY")
    fi

    if [ ${#missing_vars[@]} -gt 0 ]; then
        log_message "ОШИБКА: Отсутствуют переменные окружения для S3: ${missing_vars[*]}"
        log_message "Добавьте в ~/.bashrc:"
        for var in "${missing_vars[@]}"; do
            echo "export $var=\"your_value_here\""
        done
        return 1
    fi

    return 0
}

# Функции работы с репозиториями
get_repo_url() {
    local repo_name="$1"
    local config_json="$2"

    local repo_type=$(echo "$config_json" | jq -r ".repositories.$repo_name.type")

    case "$repo_type" in
        "local")
            local path=$(echo "$config_json" | jq -r ".repositories.$repo_name.path")
            echo "$path"
            ;;
        "s3")
            local bucket=$(echo "$config_json" | jq -r ".repositories.$repo_name.s3_bucket")
            local prefix=$(echo "$config_json" | jq -r ".repositories.$repo_name.prefix // \"\"")
            echo "s3:$bucket/$prefix"
            ;;
        "sftp")
            local host=$(echo "$config_json" | jq -r ".repositories.$repo_name.host")
            local port=$(echo "$config_json" | jq -r ".repositories.$repo_name.port // 22")
            local username=$(echo "$config_json" | jq -r ".repositories.$repo_name.username")
            local path=$(echo "$config_json" | jq -r ".repositories.$repo_name.path")
            echo "sftp:$username@$host:$port$path"
            ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

setup_repo_credentials() {
    local repo_name="$1"
    local config_json="$2"

    local repo_type=$(echo "$config_json" | jq -r ".repositories.$repo_name.type")

    case "$repo_type" in
        "s3")
            # Проверяем наличие переменных окружения
            if ! check_s3_environment; then
                return 1
            fi

            local region=$(echo "$config_json" | jq -r ".repositories.$repo_name.s3_region")
            local endpoint_url=$(echo "$config_json" | jq -r ".repositories.$repo_name.s3_endpoint_url // \"\"")

            export AWS_DEFAULT_REGION="$region"
            export AWS_REGION="$region"

            if [ -n "$endpoint_url" ] && [ "$endpoint_url" != "null" ] && [ "$endpoint_url" != "" ]; then
                export AWS_ENDPOINT_URL="$endpoint_url"
            else
                unset AWS_ENDPOINT_URL
            fi
            ;;
        "sftp")
            local ssh_key=$(echo "$config_json" | jq -r ".repositories.$repo_name.ssh_key // \"\"")

            if [ -n "$ssh_key" ] && [ "$ssh_key" != "null" ] && [ -f "$ssh_key" ]; then
                export RUSTIC_SFTP_COMMAND="ssh -i $ssh_key -o StrictHostKeyChecking=no"
            fi
            ;;
    esac
}

get_password_file() {
    local repo_name="$1"

    mkdir -p "$CREDENTIALS_DIR"
    chmod 700 "$CREDENTIALS_DIR"

    local password_file="$CREDENTIALS_DIR/${repo_name}.password"

    if [ ! -f "$password_file" ]; then
        openssl rand -base64 32 > "$password_file"
        chmod 600 "$password_file"
        log_message "Создан новый пароль для репозитория '$repo_name': $password_file"
    fi

    echo "$password_file"
}

test_repo_connection() {
    local repo_name="$1"
    local config_json="$2"

    local repo_enabled=$(echo "$config_json" | jq -r ".repositories.$repo_name.enabled")
    if [ "$repo_enabled" != "true" ]; then
        return 1
    fi

    local repo_url=$(get_repo_url "$repo_name" "$config_json")
    if [ -z "$repo_url" ]; then
        return 1
    fi

    local password_file=$(get_password_file "$repo_name")
    setup_repo_credentials "$repo_name" "$config_json"

    if rustic snapshots --repository "$repo_url" --password-file "$password_file" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

init_repository() {
    local repo_name="$1"
    local config_json="$2"

    local repo_url=$(get_repo_url "$repo_name" "$config_json")
    local password_file=$(get_password_file "$repo_name")

    setup_repo_credentials "$repo_name" "$config_json"

    log_message "Инициализация репозитория '$repo_name' с шифрованием '$RUSTIC_ENCRYPTION'..."

    if rustic init \
        --repository "$repo_url" \
        --password-file "$password_file" \
        --set-encryption "$RUSTIC_ENCRYPTION"; then

        log_message "✅ Репозиторий '$repo_name' инициализирован"
        return 0
    else
        log_message "❌ Ошибка инициализации репозитория '$repo_name'"
        return 1
    fi
}

backup_to_repository() {
    local repo_name="$1"
    local config_json="$2"
    local changed_dirs=("${@:3}")

    if [ ${#changed_dirs[@]} -eq 0 ]; then
        return 0
    fi

    local repo_url=$(get_repo_url "$repo_name" "$config_json")
    local password_file=$(get_password_file "$repo_name")
    local timestamp=$(date +'%Y%m%d_%H%M%S')

    setup_repo_credentials "$repo_name" "$config_json"

    log_message "Создание бэкапа в репозиторий '$repo_name' для ${#changed_dirs[@]} директорий (потоков: $RUSTIC_THREADS)"

    # Проверяем существование репозитория
    if ! rustic snapshots --repository "$repo_url" --password-file "$password_file" >/dev/null 2>&1; then
        if ! init_repository "$repo_name" "$config_json"; then
            return 1
        fi
    fi

    # Выполняем бэкап с всеми параметрами из конфига
    if rustic backup "${changed_dirs[@]}" \
        --repository "$repo_url" \
        --password-file "$password_file" \
        --tag "auto-$timestamp" \
        --tag "repo-$repo_name" \
        --exclude-file "$EXCLUDE_FILE" \
        --compression "$RUSTIC_COMPRESSION" \
        --threads "$RUSTIC_THREADS"; then

        log_message "✅ Бэкап в '$repo_name' успешно завершен"

        # Ротация с использованием потоков
        log_message "Выполнение ротации в репозитории '$repo_name'..."
        rustic forget \
            --repository "$repo_url" \
            --password-file "$password_file" \
            --keep-daily "$KEEP_DAILY" \
            --keep-weekly "$KEEP_WEEKLY" \
            --keep-monthly "$KEEP_MONTHLY" \
            --keep-yearly "$KEEP_YEARLY" \
            --threads "$RUSTIC_THREADS" \
            --prune

        return 0
    else
        log_message "❌ Ошибка бэкапа в репозиторий '$repo_name'"
        return 1
    fi
}

show_schedule_info() {
    echo ""
    echo "=== ИНФОРМАЦИЯ О РАСПИСАНИИ ==="
    echo "Автозапуск включен: $SCHEDULE_ENABLED"
    echo "Текущий пресет: $SCHEDULE_PRESET"

    if echo "$CONFIG_JSON" | jq -e '.schedule.presets' >/dev/null 2>&1; then
        local schedule_value=$(echo "$CONFIG_JSON" | jq -r ".schedule.presets.$SCHEDULE_PRESET // \"не найден\"")
        echo "Расписание: $schedule_value"
    fi

    echo ""
    echo "Для настройки расписания используйте:"
    echo "  ./setup_systemd.sh schedule"
}

get_enabled_repositories() {
    local config_json="$1"
    if echo "$config_json" | jq -e '.repositories' >/dev/null 2>&1; then
        echo "$config_json" | jq -r '.repositories | to_entries[] | select(.value.enabled == true) | .key'
    fi
}

get_primary_repository() {
    local config_json="$1"
    echo "$config_json" | jq -r '.backup.primary_repo // "local"'
}

show_repositories_status() {
    echo ""
    log_message "=== СТАТУС РЕПОЗИТОРИЕВ ==="

    local config_json=$(envsubst < "$CONFIG_FILE")

    # Проверяем, есть ли новая структура repositories
    if ! echo "$config_json" | jq -e '.repositories' >/dev/null 2>&1; then
        echo "Используется старая структура конфигурации (repo_path)"
        echo "Обновите config.json для поддержки множественных репозиториев"
        return
    fi

    local primary_repo=$(get_primary_repository "$config_json")

    echo "$config_json" | jq -r '.repositories | to_entries[] | "\(.key)|\(.value.type)|\(.value.enabled)|\(.value.description // "")"' | \
    while IFS='|' read -r name type enabled description; do
        local status_icon="❌"
        local primary_mark=""

        if [ "$enabled" = "true" ]; then
            if test_repo_connection "$name" "$config_json" >/dev/null 2>&1; then
                status_icon="✅"
            else
                status_icon="⚠️"
            fi
        fi

        if [ "$name" = "$primary_repo" ]; then
            primary_mark=" [ОСНОВНОЙ]"
        fi

        echo "  $status_icon $name ($type)$primary_mark - $description"
    done
}

# --- ДОПОЛНИТЕЛЬНЫЕ ФУНКЦИИ ---
show_backup_info() {
    if [ ! -d "$RUSTIC_REPO" ]; then
        echo "Репозиторий еще не создан"
        return
    fi

    echo ""
    echo "=== ИНФОРМАЦИЯ О БЭКАПАХ ==="

    # Определяем password file
    local password_file
    if echo "$CONFIG_JSON" | jq -e '.repositories' >/dev/null 2>&1; then
        # Новая структура
        local primary_repo=$(get_primary_repository "$CONFIG_JSON")
        password_file=$(get_password_file "$primary_repo")
    else
        # Старая структура
        password_file="$SCRIPT_DIR/.password"
    fi

    if command -v rustic >/dev/null 2>&1 && [ -f "$password_file" ]; then
        echo "Последние снапшоты:"
        rustic snapshots --repository "$RUSTIC_REPO" --password-file "$password_file" | tail -10

        echo ""
        echo "Статистика репозитория:"
        rustic stats --repository "$RUSTIC_REPO" --password-file "$password_file"
    else
        echo "Rustic недоступен или отсутствует пароль"
    fi
}

interactive_restore() {
    if [ ! -d "$RUSTIC_REPO" ]; then
        echo "❌ Репозиторий не найден: $RUSTIC_REPO"
        return 1
    fi

    if ! command -v rustic >/dev/null 2>&1; then
        echo "❌ Rustic не установлен"
        return 1
    fi

    # Определяем password file
    local password_file
    if echo "$CONFIG_JSON" | jq -e '.repositories' >/dev/null 2>&1; then
        local primary_repo=$(get_primary_repository "$CONFIG_JSON")
        password_file=$(get_password_file "$primary_repo")
    else
        password_file="$SCRIPT_DIR/.password"
    fi

    if [ ! -f "$password_file" ]; then
        echo "❌ Файл пароля не найден: $password_file"
        return 1
    fi

    echo ""
    echo "=== ВОССТАНОВЛЕНИЕ ИЗ БЭКАПА ==="

    # Показываем снапшоты
    echo "Доступные снапшоты:"
    rustic snapshots --repository "$RUSTIC_REPO" --password-file "$password_file"

    echo ""
    read -p "ID снапшота (или 'latest' для последнего): " snapshot_id
    read -p "Путь для восстановления [./restored]: " restore_path

    if [ -z "$restore_path" ]; then
        restore_path="./restored"
    fi

    mkdir -p "$restore_path"

    echo "Восстановление снапшота '$snapshot_id' в '$restore_path'..."

    if rustic restore "$snapshot_id" \
        --repository "$RUSTIC_REPO" \
        --password-file "$password_file" \
        --target "$restore_path"; then

        echo "✅ Восстановление завершено успешно!"
        echo "📁 Данные восстановлены в: $(realpath "$restore_path")"
    else
        echo "❌ Ошибка при восстановлении!"
        return 1
    fi
}

# --- УПРАВЛЕНИЕ РЕПОЗИТОРИЯМИ ---
manage_repositories() {
    while true; do
        echo ""
        echo "=========================================="
        echo "      УПРАВЛЕНИЕ РЕПОЗИТОРИЯМИ"
        echo "=========================================="
        echo "1) Показать статус всех репозиториев"
        echo "2) Тестировать подключения"
        echo "3) Настроить S3 репозиторий"
        echo "4) Включить/отключить репозиторий"
        echo "0) Назад"
        echo "=========================================="

        read -p "Выберите действие (0-4): " choice

        case $choice in
            1) show_repositories_status ;;
            2) test_all_repositories ;;
            3) configure_s3_repository ;;
            4) toggle_repository ;;
            0) return ;;
            *) echo "❌ Неверный выбор" ;;
        esac

        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

test_all_repositories() {
    echo ""
    echo "=== ТЕСТИРОВАНИЕ ВСЕХ РЕПОЗИТОРИЕВ ==="

    local config_json=$(envsubst < "$CONFIG_FILE")

    if echo "$config_json" | jq -e '.repositories' >/dev/null 2>&1; then
        echo "$config_json" | jq -r '.repositories | keys[]' | while read -r repo_name; do
            if test_repo_connection "$repo_name" "$config_json" >/dev/null 2>&1; then
                echo "  ✅ $repo_name"
            else
                echo "  ❌ $repo_name"
            fi
        done
    else
        echo "Старая структура конфигурации - только локальный репозиторий"
    fi
}

configure_s3_repository() {
    echo "Функция настройки S3 репозитория будет добавлена в следующей версии"
}

toggle_repository() {
    echo "Функция включения/отключения репозитория будет добавлена в следующей версии"
}

# --- ОСНОВНЫЕ ФУНКЦИИ ---
log_message() {
    local message="$1"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"

    # Десктопные уведомления
    if [ "$ENABLE_DESKTOP_NOTIFICATIONS" = "true" ] && command -v notify-send >/dev/null 2>&1; then
        if [[ "$message" == *"ОШИБКА"* ]] || [[ "$message" == *"ERROR"* ]]; then
            notify-send "Backup Manager" "❌ $message" --urgency=critical
        elif [[ "$message" == *"успешно"* ]] || [[ "$message" == *"завершен"* ]]; then
            notify-send "Backup Manager" "✅ $message"
        fi
    fi
}

detect_architecture() {
    case $(uname -m) in
        x86_64) echo "x86_64-unknown-linux-gnu" ;;
        aarch64|arm64) echo "aarch64-unknown-linux-gnu" ;;
        *) echo "unknown" ;;
    esac
}

check_rustic_installed() {
    if command -v rustic >/dev/null 2>&1; then
        log_message "Rustic найден: $(rustic --version)"
        return 0
    else
        return 1
    fi
}

install_rustic() {
    local arch=$(detect_architecture)
    if [ "$arch" = "unknown" ]; then
        log_message "ОШИБКА: Неподдерживаемая архитектура $(uname -m)"
        return 1
    fi

    local installer_path="$INSTALLERS_DIR/rustic-$arch"

    if [ ! -f "$installer_path" ]; then
        log_message "ОШИБКА: Установочник не найден: $installer_path"
        return 1
    fi

    log_message "Устанавливаем rustic из локального файла..."

    mkdir -p "$HOME/.local/bin"
    cp "$installer_path" "$HOME/.local/bin/rustic"
    chmod +x "$HOME/.local/bin/rustic"

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        export PATH="$HOME/.local/bin:$PATH"
    fi

    if "$HOME/.local/bin/rustic" --version >/dev/null 2>&1; then
        log_message "Rustic успешно установлен"
        return 0
    else
        log_message "ОШИБКА: Не удалось установить rustic"
        return 1
    fi
}

calculate_checksum() {
    local dir_path="$1"
    if [ "$ENABLE_CHECKSUM_VERIFICATION" != "true" ]; then
        echo "checksum_disabled"
        return 0
    fi

    if [ -d "$dir_path" ] && [ -r "$dir_path" ]; then
        find "$dir_path" -type f -exec stat --format='%n %s %Y' {} + | sort | md5sum | cut -d' ' -f1
    else
        echo ""
    fi
}

is_source_safe() {
    local dir_path="$1"

    if [ ! -d "$dir_path" ] || [ ! -r "$dir_path" ]; then
        log_message "ПРЕДУПРЕЖДЕНИЕ: Директория '$dir_path' недоступна"
        return 1
    fi

    if [ ! "$(ls -A "$dir_path")" ]; then
        log_message "ИНФО: Директория '$dir_path' пуста"
        return 0
    fi

    if [ "$ENABLE_SIZE_CHECK" = "true" ]; then
        local total_size_kb=$(du -sk "$dir_path" | cut -f1)

        if ! [[ "$total_size_kb" =~ ^[0-9]+$ ]] || [ "$total_size_kb" -lt "$MIN_TOTAL_DIR_SIZE_KB" ]; then
            log_message "ПРЕДУПРЕЖДЕНИЕ: Размер '$dir_path' (${total_size_kb}KB) меньше порога"
            return 1
        fi
    fi

    return 0
}

# Интерактивное меню
show_menu() {
    echo ""
    echo "=========================================="
    echo "        МЕНЕДЖЕР БЭКАПОВ RUSTIC"
    echo "=========================================="
    echo "1) Запустить бэкап"
    echo "2) Показать информацию о бэкапах"
    echo "3) Восстановить из бэкапа"
    echo "4) 🗄️  Управление репозиториями"
    echo "5) Проверить конфигурацию"
    echo "6) Показать конфигурацию"
    echo "7) 📅 Показать расписание"
    echo "8) Редактировать конфигурацию"
    echo "9) ⏰ Настроить автозапуск (systemd)"
    echo "0) Выход"
    echo "=========================================="
}

# --- ОСНОВНАЯ ЛОГИКА ---
main() {
    check_dependencies
    load_config

    # Если передан аргумент, выполняем соответствующее действие
    case "${1:-menu}" in
        "backup"|"run")
            run_backup
            ;;
        "info")
            show_config_summary
            show_backup_info
            ;;
        "restore")
            interactive_restore
            ;;
        "check")
            validate_config
            ;;
        "menu"|"")
            # Интерактивное меню
            while true; do
                show_menu
                read -p "Выберите действие (0-9): " choice

                case $choice in
                    1) run_backup ;;
                    2) show_backup_info ;;
                    3) interactive_restore ;;
                    4) manage_repositories ;;
                    5) validate_config ;;
                    6) show_config_summary ;;
                    7) show_schedule_info ;;
                    8) ${EDITOR:-nano} "$CONFIG_FILE" ;;
                    9) "$SCRIPT_DIR/setup_systemd.sh" install ;;
                    0) echo "До свидания!"; exit 0 ;;
                    *) echo "❌ Неверный выбор" ;;
                esac

                echo ""
                read -p "Нажмите Enter для продолжения..."
            done
            ;;
        *)
            echo "Использование: $0 [backup|info|restore|check|menu]"
            exit 1
            ;;
    esac
}

run_backup() {
    log_message "=== АВТОНОМНЫЙ МЕНЕДЖЕР БЭКАПОВ С RUSTIC ==="

    if ! validate_config; then
        exit 1
    fi

    show_config_summary

    # Проверяем и устанавливаем rustic
    if ! check_rustic_installed; then
        if ! install_rustic; then
            log_message "КРИТИЧЕСКАЯ ОШИБКА: Не удалось установить rustic"
            exit 1
        fi
    fi

    # Генерируем файл исключений
    EXCLUDE_FILE=$(generate_exclude_file)

    # Создаем необходимые директории
    mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")" "$CREDENTIALS_DIR"

    # Основной цикл бэкапа
    TIMESTAMP=$(date +'%Y%m%d_%H%M%S')
    CHANGED_DIRS=()

    # Проверяем изменения
    for source_dir in "${SOURCE_DIRS[@]}"; do
        if [ ! -d "$source_dir" ]; then
            log_message "ПРЕДУПРЕЖДЕНИЕ: Директория '$source_dir' не найдена"
            continue
        fi

        dest_name=$(basename "$source_dir")
        state_file="${STATE_DIR}/${dest_name}.state"

        current_checksum=$(calculate_checksum "$source_dir")
        previous_checksum=""
        [ -f "$state_file" ] && previous_checksum=$(cat "$state_file")

        if [ "$current_checksum" != "$previous_checksum" ]; then
            if is_source_safe "$source_dir"; then
                log_message "Изменения в '$source_dir' - добавляем в бэкап"
                CHANGED_DIRS+=("$source_dir")
            fi
        fi
    done

    # Выполняем бэкап если есть изменения
    if [ ${#CHANGED_DIRS[@]} -gt 0 ]; then
        local config_json=$(envsubst < "$CONFIG_FILE")

        # Проверяем, используется ли новая структура с repositories
        if echo "$config_json" | jq -e '.repositories' >/dev/null 2>&1; then
            # Новая структура - поддержка множественных репозиториев
            local multi_repo_enabled=$(echo "$config_json" | jq -r '.multi_repo.enabled // false')

            if [ "$multi_repo_enabled" = "true" ]; then
                log_message "Режим мульти-репозитория включен"

                local target_repos=$(echo "$config_json" | jq -r '.multi_repo.repositories[]' 2>/dev/null || get_enabled_repositories "$config_json")
                local successful_repos=()
                local failed_repos=()

                if [ "$PARALLEL_UPLOADS" = "true" ]; then
                    log_message "Параллельные загрузки включены"

                    # Массив для хранения PID процессов
                    local pids=()

                    for repo_name in $target_repos; do
                        local repo_enabled=$(echo "$config_json" | jq -r ".repositories.$repo_name.enabled // false")

                        if [ "$repo_enabled" = "true" ]; then
                            log_message "Запуск параллельного бэкапа в '$repo_name'"

                            # Запускаем в фоне
                            (
                                if backup_to_repository "$repo_name" "$config_json" "${CHANGED_DIRS[@]}"; then
                                    echo "SUCCESS:$repo_name" > "/tmp/backup_result_$$_$repo_name"
                                else
                                    echo "FAILED:$repo_name" > "/tmp/backup_result_$$_$repo_name"
                                fi
                            ) &

                            pids+=($!)
                        fi
                    done

                    # Ждем завершения всех процессов
                    log_message "Ожидание завершения параллельных бэкапов..."
                    for pid in "${pids[@]}"; do
                        wait "$pid"
                    done

                    # Собираем результаты
                    for repo_name in $target_repos; do
                        if [ -f "/tmp/backup_result_$$_$repo_name" ]; then
                            local result=$(cat "/tmp/backup_result_$$_$repo_name")
                            if [[ "$result" == "SUCCESS:"* ]]; then
                                successful_repos+=("$repo_name")
                            else
                                failed_repos+=("$repo_name")
                            fi
                            rm -f "/tmp/backup_result_$$_$repo_name"
                        fi
                    done

                else
                    # Последовательные загрузки
                    log_message "Последовательные загрузки"

                    for repo_name in $target_repos; do
                        local repo_enabled=$(echo "$config_json" | jq -r ".repositories.$repo_name.enabled // false")

                        if [ "$repo_enabled" = "true" ]; then
                            if backup_to_repository "$repo_name" "$config_json" "${CHANGED_DIRS[@]}"; then
                                successful_repos+=("$repo_name")
                            else
                                failed_repos+=("$repo_name")
                            fi
                        fi
                    done
                fi

                log_message "Результаты: успешно=${#successful_repos[@]}, ошибок=${#failed_repos[@]}"
            else
                # Одиночный репозиторий режим (новая структура)
                local primary_repo=$(get_primary_repository "$config_json")
                backup_to_repository "$primary_repo" "$config_json" "${CHANGED_DIRS[@]}"
            fi
        else
            # Старая структура - совместимость
            log_message "Создание бэкапа для ${#CHANGED_DIRS[@]} директорий"

            # Определяем password file для старой структуры
            local password_file="$SCRIPT_DIR/.password"

            # Инициализируем репозиторий если нужно
            if [ ! -d "$RUSTIC_REPO" ]; then
                log_message "Инициализация rustic репозитория..."

                if [ ! -f "$password_file" ]; then
                    openssl rand -base64 32 > "$password_file"
                    chmod 600 "$password_file"
                fi

                rustic init --repository "$RUSTIC_REPO" --password-file "$password_file"
            fi

            # Выполняем бэкап (старая логика)
            rustic backup "${CHANGED_DIRS[@]}" \
                --repository "$RUSTIC_REPO" \
                --password-file "$password_file" \
                --tag "auto-$TIMESTAMP" \
                --exclude-file "$EXCLUDE_FILE" \
                --compression "$RUSTIC_COMPRESSION"

            if [ $? -eq 0 ]; then
                log_message "Бэкап успешно завершен"

                # Ротация
                rustic forget \
                    --repository "$RUSTIC_REPO" \
                    --password-file "$password_file" \
                    --keep-daily "$KEEP_DAILY" \
                    --keep-weekly "$KEEP_WEEKLY" \
                    --keep-monthly "$KEEP_MONTHLY" \
                    --keep-yearly "$KEEP_YEARLY" \
                    --prune
            else
                log_message "ОШИБКА при создании бэкапа"
            fi
        fi

        # Обновляем state файлы при успешном бэкапе
        for source_dir in "${CHANGED_DIRS[@]}"; do
            dest_name=$(basename "$source_dir")
            state_file="${STATE_DIR}/${dest_name}.state"
            current_checksum=$(calculate_checksum "$source_dir")
            echo "$current_checksum" > "$state_file"
        done
    else
        log_message "Изменений не обнаружено - бэкап не требуется"
    fi

    log_message "Скрипт завершил работу"
}

# Запуск
main "$@"
