# Создание бэкапов

Задать пароль можно в директории `.password`.
Конфиг задаётся в config.json.

```bash
# Запуск бэкапа
./backup.sh
# Просмотр снапшотов
rustic snapshots --repository ~/rustic-backup --password-file password.txt
```

# Настройка автозапуска

``` bash
chmod +x setup_systemd.sh
./setup_systemd.sh install

# Быстрые команды
chmod +x systemd_helper.sh
./systemd_helper.sh start      # Запустить сейчас
./systemd_helper.sh status     # Статус
./systemd_helper.sh logs       # Логи
./systemd_helper.sh next       # Следующий запуск

# Или через основной скрипт
./backup.sh                    # Меню с опциями systemd
```

# Восстановление

`init_recovery.sh`позволяет создать скрипты для восстановления (под Linux, macOS, Windows).
Он создаёт папку recovery-kit с необходимыми файлами для восстановления.

Для восстановления:
1. Скопируйте папку recovery-kit на целевую систему
2. Запустите: ./recovery.sh
3. Следуйте инструкциям скрипта

---

Поддерживаемые платформы

Linux x64: rustic-linux-x64
Linux ARM64: rustic-linux-arm64
macOS Intel: rustic-macos-intel
macOS Apple Silicon: rustic-macos-apple
Windows: rustic-windows.exe

Rustic https://github.com/rustic-rs/rustic
Утилита для создания бэкапов на Rust

Linux (обязательные):

rustic-v0.9.5-x86_64-unknown-linux-gnu.tar.gz - 64-bit Intel/AMD
rustic-v0.9.5-aarch64-unknown-linux-gnu.tar.gz - ARM64 (серверы, Raspberry Pi)

macOS:

rustic-v0.9.5-x86_64-apple-darwin.tar.gz - Intel Mac
rustic-v0.9.5-aarch64-apple-darwin.tar.gz - Apple Silicon (M1/M2/M3)

Windows:

rustic-v0.9.5-x86_64-pc-windows-msvc.tar.gz - Windows 64-bit
