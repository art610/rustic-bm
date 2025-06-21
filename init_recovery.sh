#!/bin/bash

# === ПОДГОТОВКА RECOVERY KIT ===

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLERS_DIR="$SCRIPT_DIR/installers"
KIT_DIR="$SCRIPT_DIR/recovery-kit"

echo "🛠️  Подготовка recovery kit..."

mkdir -p "$KIT_DIR"

# Функция извлечения и переименования
extract_and_rename() {
    local archive="$1"
    local target_name="$2"

    if [ ! -f "$INSTALLERS_DIR/$archive" ]; then
        echo "⚠️  Пропуск: $archive не найден"
        return 1
    fi

    echo "📦 Обработка $archive -> $target_name"

    # Создаем временную папку
    local temp_dir=$(mktemp -d)

    # Извлекаем архив во временную папку
    tar -xzf "$INSTALLERS_DIR/$archive" -C "$temp_dir"

    # Ищем бинарник rustic
    local rustic_binary=""
    if [ -f "$temp_dir/rustic.exe" ]; then
        rustic_binary="$temp_dir/rustic.exe"
    elif [ -f "$temp_dir/rustic" ]; then
        rustic_binary="$temp_dir/rustic"
    else
        echo "❌ Не найден бинарник в архиве $archive"
        rm -rf "$temp_dir"
        return 1
    fi

    # Копируем в recovery-kit
    cp "$rustic_binary" "$KIT_DIR/$target_name"
    chmod +x "$KIT_DIR/$target_name"

    # Очищаем временную папку
    rm -rf "$temp_dir"

    echo "✅ Готов: $target_name"
    return 0
}

# Карта архивов и целевых имен
declare -A ARCHIVE_MAP=(
    ["rustic-v0.9.5-x86_64-unknown-linux-gnu.tar.gz"]="rustic-linux-x64"
    ["rustic-v0.9.5-aarch64-unknown-linux-gnu.tar.gz"]="rustic-linux-arm64"
    ["rustic-v0.9.5-x86_64-apple-darwin.tar.gz"]="rustic-macos-intel"
    ["rustic-v0.9.5-aarch64-apple-darwin.tar.gz"]="rustic-macos-apple"
    ["rustic-v0.9.5-x86_64-pc-windows-msvc.tar.gz"]="rustic-windows.exe"
)

# Обрабатываем все архивы
echo "📦 Извлечение бинарников из архивов..."
extracted_count=0

for archive in "${!ARCHIVE_MAP[@]}"; do
    target_name="${ARCHIVE_MAP[$archive]}"
    if extract_and_rename "$archive" "$target_name"; then
        extracted_count=$((extracted_count + 1))
    fi
done

if [ $extracted_count -eq 0 ]; then
    echo "❌ Не удалось извлечь ни одного бинарника!"
    echo "📍 Проверьте содержимое папки installers:"
    ls -la "$INSTALLERS_DIR"
    exit 1
fi

echo "✅ Извлечено $extracted_count бинарников"

# Копируем скрипт восстановления для Unix
echo "📄 Создание recovery.sh для Linux/macOS..."
cat > "$KIT_DIR/recovery.sh" << 'EOF'
#!/bin/bash

# === ПОРТАТИВНЫЙ ВОССТАНОВИТЕЛЬ RUSTIC ===
# Работает БЕЗ подключения к сети

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSWORD_FILE="$SCRIPT_DIR/password.txt"

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Определение архитектуры
detect_rustic_binary() {
    local os_type=$(uname -s)
    local arch=$(uname -m)

    case "$os_type" in
        "Linux")
            case "$arch" in
                x86_64) echo "rustic-linux-x64" ;;
                aarch64|arm64) echo "rustic-linux-arm64" ;;
                *) echo "unknown" ;;
            esac
            ;;
        "Darwin")
            case "$arch" in
                x86_64) echo "rustic-macos-intel" ;;
                arm64) echo "rustic-macos-apple" ;;
                *) echo "unknown" ;;
            esac
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Поиск rustic
find_rustic() {
    # 1. Проверяем системный rustic
    if command -v rustic >/dev/null 2>&1; then
        echo "rustic"
        return 0
    fi

    # 2. Ищем подходящий бинарник
    local target_binary=$(detect_rustic_binary)
    local rustic_path="$SCRIPT_DIR/$target_binary"

    if [ -f "$rustic_path" ]; then
        chmod +x "$rustic_path"
        echo "$rustic_path"
        return 0
    fi

    # 3. Ищем любой rustic в папке
    for file in "$SCRIPT_DIR"/rustic*; do
        if [ -f "$file" ] && [ -x "$file" ]; then
            echo "$file"
            return 0
        fi
    done

    return 1
}

# Поиск репозитория
find_repository() {
    echo ""
    log_info "=== ПОИСК РЕПОЗИТОРИЯ RUSTIC ==="

    local possible_repos=(
        "$HOME/rustic-backup"
        "$SCRIPT_DIR/rustic-backup"
        "./rustic-backup"
        "../rustic-backup"
    )

    echo "Поиск репозитория в стандартных местах:"
    for repo in "${possible_repos[@]}"; do
        if [ -d "$repo" ]; then
            log_success "Найден: $repo"
            echo "$repo"
            return 0
        else
            echo "  ✗ $repo"
        fi
    done

    echo ""
    log_info "Репозиторий не найден автоматически."
    read -p "Введите путь к репозиторию rustic: " manual_repo

    if [ -d "$manual_repo" ]; then
        echo "$manual_repo"
        return 0
    else
        log_error "Репозиторий не найден: $manual_repo"
        return 1
    fi
}

# Проверка пароля
get_password() {
    if [ -f "$PASSWORD_FILE" ]; then
        log_success "Найден файл пароля: $PASSWORD_FILE"
        echo "$PASSWORD_FILE"
    else
        log_info "Файл пароля не найден."
        read -s -p "Введите пароль репозитория: " password
        echo ""
        echo "$password" > "/tmp/rustic_password_$$"
        echo "/tmp/rustic_password_$$"
    fi
}

# Основные функции
list_snapshots() {
    local rustic="$1"
    local repo="$2"
    local password_file="$3"

    log_info "Список снапшотов в репозитории:"
    "$rustic" snapshots --repository "$repo" --password-file "$password_file"
}

restore_data() {
    local rustic="$1"
    local repo="$2"
    local password_file="$3"

    echo ""
    log_info "=== ВОССТАНОВЛЕНИЕ ДАННЫХ ==="

    list_snapshots "$rustic" "$repo" "$password_file"

    echo ""
    read -p "ID снапшота (или 'latest' для последнего): " snapshot_id
    read -p "Путь для восстановления [./restored]: " restore_path

    if [ -z "$restore_path" ]; then
        restore_path="./restored"
    fi

    mkdir -p "$restore_path"

    log_info "Восстановление снапшота '$snapshot_id' в '$restore_path'..."

    if "$rustic" restore "$snapshot_id" \
        --repository "$repo" \
        --password-file "$password_file" \
        --target "$restore_path"; then

        log_success "Восстановление завершено успешно!"
        log_info "Данные восстановлены в: $(realpath "$restore_path")"

        echo ""
        log_info "Восстановленные файлы:"
        find "$restore_path" -type f | head -20
        local total_files=$(find "$restore_path" -type f | wc -l)
        if [ "$total_files" -gt 20 ]; then
            echo "... и еще $(($total_files - 20)) файлов"
        fi

    else
        log_error "Ошибка при восстановлении!"
        return 1
    fi
}

# Главное меню
show_menu() {
    echo ""
    echo "=========================================="
    echo "    ПОРТАТИВНЫЙ ВОССТАНОВИТЕЛЬ RUSTIC"
    echo "=========================================="
    echo "1) Показать информацию о системе"
    echo "2) Список снапшотов"
    echo "3) Восстановить данные"
    echo "4) Проверить репозиторий"
    echo "0) Выход"
    echo "=========================================="
}

check_system() {
    echo ""
    log_info "=== ИНФОРМАЦИЯ О СИСТЕМЕ ==="
    echo "ОС: $(uname -s) $(uname -r)"
    echo "Архитектура: $(uname -m)"
    echo "Пользователь: $USER"
    echo "Домашняя папка: $HOME"
    echo "Текущая папка: $(pwd)"
    echo "Ожидаемый бинарник: $(detect_rustic_binary)"

    local rustic_bin=$(find_rustic 2>/dev/null || echo "не найден")
    echo "Rustic: $rustic_bin"

    if [ "$rustic_bin" != "не найден" ]; then
        echo "Версия: $("$rustic_bin" --version 2>/dev/null || echo "ошибка")"
    fi
}

verify_repository() {
    local rustic="$1"
    local repo="$2"
    local password_file="$3"

    log_info "Проверка целостности репозитория..."

    if "$rustic" check --repository "$repo" --password-file "$password_file"; then
        log_success "Репозиторий в порядке!"
    else
        log_error "Обнаружены проблемы в репозитории!"
        return 1
    fi
}

# Основная логика
main() {
    log_info "Запуск портативного восстановителя..."

    local rustic_binary
    if ! rustic_binary=$(find_rustic); then
        log_error "Бинарник rustic не найден!"
        log_info "Ожидаемое имя: $(detect_rustic_binary)"
        exit 1
    fi

    log_success "Найден rustic: $rustic_binary"

    local repository
    if ! repository=$(find_repository); then
        exit 1
    fi

    local password_file
    if ! password_file=$(get_password); then
        exit 1
    fi

    while true; do
        show_menu
        read -p "Выберите действие (0-4): " choice

        case $choice in
            1) check_system ;;
            2) list_snapshots "$rustic_binary" "$repository" "$password_file" ;;
            3) restore_data "$rustic_binary" "$repository" "$password_file" ;;
            4) verify_repository "$rustic_binary" "$repository" "$password_file" ;;
            0)
                log_info "До свидания!"
                [ -f "/tmp/rustic_password_$$" ] && rm "/tmp/rustic_password_$$"
                exit 0
                ;;
            *) log_error "Неверный выбор" ;;
        esac

        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

main "$@"
EOF

chmod +x "$KIT_DIR/recovery.sh"

# Создаем Windows .bat файл
echo "🪟 Создание recovery.bat для Windows..."
cat > "$KIT_DIR/recovery.bat" << 'EOF'
@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: === ПОРТАТИВНЫЙ ВОССТАНОВИТЕЛЬ RUSTIC для Windows ===

set "SCRIPT_DIR=%~dp0"
set "PASSWORD_FILE=%SCRIPT_DIR%password.txt"
set "RUSTIC_BINARY=%SCRIPT_DIR%rustic-windows.exe"

echo.
echo ==========================================
echo     ПОРТАТИВНЫЙ ВОССТАНОВИТЕЛЬ RUSTIC
echo ==========================================

:: Проверяем наличие rustic
if not exist "%RUSTIC_BINARY%" (
    echo [ERROR] Не найден rustic-windows.exe в папке!
    echo Убедитесь что файл rustic-windows.exe находится рядом с этим скриптом.
    pause
    exit /b 1
)

echo [INFO] Найден rustic: %RUSTIC_BINARY%

:: Проверяем версию
echo [INFO] Версия rustic:
"%RUSTIC_BINARY%" --version
echo.

:: Поиск репозитория
echo [INFO] === ПОИСК РЕПОЗИТОРИЯ ===
set "REPOSITORY="

:: Возможные местоположения
set "REPOS[0]=%USERPROFILE%\rustic-backup"
set "REPOS[1]=%SCRIPT_DIR%rustic-backup"
set "REPOS[2]=.\rustic-backup"
set "REPOS[3]=..\rustic-backup"

echo Поиск репозитория в стандартных местах:
for /L %%i in (0,1,3) do (
    if exist "!REPOS[%%i]!" (
        echo   [SUCCESS] Найден: !REPOS[%%i]!
        set "REPOSITORY=!REPOS[%%i]!"
        goto :found_repo
    ) else (
        echo   [x] !REPOS[%%i]!
    )
)

:: Ручной ввод пути
echo.
echo [INFO] Репозиторий не найден автоматически.
set /p "MANUAL_REPO=Введите путь к репозиторию rustic: "
if exist "%MANUAL_REPO%" (
    set "REPOSITORY=%MANUAL_REPO%"
    goto :found_repo
) else (
    echo [ERROR] Репозиторий не найден: %MANUAL_REPO%
    pause
    exit /b 1
)

:found_repo
echo [SUCCESS] Используется репозиторий: %REPOSITORY%

:: Проверка пароля
if exist "%PASSWORD_FILE%" (
    echo [SUCCESS] Найден файл пароля: %PASSWORD_FILE%
    set "PASSWORD_ARG=--password-file "%PASSWORD_FILE%""
) else (
    echo [INFO] Файл пароля не найден.
    set /p "PASSWORD=Введите пароль репозитория: "
    echo !PASSWORD! > "%TEMP%\rustic_password.txt"
    set "PASSWORD_ARG=--password-file "%TEMP%\rustic_password.txt""
)

:: Главное меню
:main_menu
echo.
echo ==========================================
echo 1^) Список снапшотов
echo 2^) Восстановить данные
echo 3^) Проверить репозиторий
echo 4^) Информация о системе
echo 0^) Выход
echo ==========================================
set /p "CHOICE=Выберите действие (0-4): "

if "%CHOICE%"=="1" goto :list_snapshots
if "%CHOICE%"=="2" goto :restore_data
if "%CHOICE%"=="3" goto :check_repo
if "%CHOICE%"=="4" goto :system_info
if "%CHOICE%"=="0" goto :exit
echo [ERROR] Неверный выбор
goto :main_menu

:list_snapshots
echo.
echo [INFO] === СПИСОК СНАПШОТОВ ===
"%RUSTIC_BINARY%" snapshots --repository "%REPOSITORY%" %PASSWORD_ARG%
pause
goto :main_menu

:restore_data
echo.
echo [INFO] === ВОССТАНОВЛЕНИЕ ДАННЫХ ===

:: Показываем снапшоты
echo Доступные снапшоты:
"%RUSTIC_BINARY%" snapshots --repository "%REPOSITORY%" %PASSWORD_ARG%

echo.
set /p "SNAPSHOT_ID=ID снапшота (или 'latest' для последнего): "
set /p "RESTORE_PATH=Путь для восстановления [.\restored]: "

if "%RESTORE_PATH%"=="" set "RESTORE_PATH=.\restored"

:: Создаем папку
if not exist "%RESTORE_PATH%" mkdir "%RESTORE_PATH%"

echo [INFO] Восстановление снапшота '%SNAPSHOT_ID%' в '%RESTORE_PATH%'...
"%RUSTIC_BINARY%" restore "%SNAPSHOT_ID%" --repository "%REPOSITORY%" %PASSWORD_ARG% --target "%RESTORE_PATH%"

if %ERRORLEVEL%==0 (
    echo [SUCCESS] Восстановление завершено успешно!
    echo [INFO] Данные восстановлены в: %RESTORE_PATH%
    echo.
    echo [INFO] Восстановленные файлы:
    dir /s /b "%RESTORE_PATH%" | findstr /v /c:"$" | more
) else (
    echo [ERROR] Ошибка при восстановлении!
)
pause
goto :main_menu

:check_repo
echo.
echo [INFO] === ПРОВЕРКА РЕПОЗИТОРИЯ ===
"%RUSTIC_BINARY%" check --repository "%REPOSITORY%" %PASSWORD_ARG%
if %ERRORLEVEL%==0 (
    echo [SUCCESS] Репозиторий в порядке!
) else (
    echo [ERROR] Обнаружены проблемы в репозитории!
)
pause
goto :main_menu

:system_info
echo.
echo [INFO] === ИНФОРМАЦИЯ О СИСТЕМЕ ===
echo ОС: Windows
echo Версия:
ver
echo Пользователь: %USERNAME%
echo Домашняя папка: %USERPROFILE%
echo Текущая папка: %CD%
echo Rustic: %RUSTIC_BINARY%
echo Версия rustic:
"%RUSTIC_BINARY%" --version
pause
goto :main_menu

:exit
echo [INFO] До свидания!
:: Очищаем временный пароль
if exist "%TEMP%\rustic_password.txt" del "%TEMP%\rustic_password.txt"
pause
exit /b 0
EOF

echo "✅ Создан recovery.bat для Windows"

# Копируем пароль если есть
if [ -f "$SCRIPT_DIR/config/password.txt" ]; then
    cp "$SCRIPT_DIR/config/password.txt" "$KIT_DIR/"
    echo "🔐 Скопирован файл пароля"
elif [ -f "$SCRIPT_DIR/password.txt" ]; then
    cp "$SCRIPT_DIR/password.txt" "$KIT_DIR/"
    echo "🔐 Скопирован файл пароля"
else
    echo "⚠️  Файл пароля не найден - будет запрашиваться вручную"
fi

# Создаем README
cat > "$KIT_DIR/README.md" << 'EOF'
# Recovery Kit для Rustic

## Быстрый старт

### Linux / macOS
```bash
chmod +x recovery.sh
./recovery.sh
```

### Windows
```
recovery.bat
```
EOF
