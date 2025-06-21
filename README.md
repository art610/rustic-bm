# 🗄️ Rustic Backup Manager

Autonomous backup manager with multiple repository support, based on [rustic](https://github.com/rustic-rs/rustic).

## ✨ Features

- 🔄 **Incremental backups** with deduplication and compression
- 🗄️ **Multiple repositories**: local, S3, SSH/SFTP servers
- ⚡ **Parallel uploads** to multiple repositories simultaneously
- 🔒 **Client-side encryption** (AES-256)
- ⏰ **Automation** via systemd with flexible scheduling
- 🎯 **Smart sync** - backup only on changes (checksum-based)
- 📦 **Portable recovery kit** for offline restoration
- 🖥️ **Interactive menu** and command-line support
- 🔧 **JSON configuration** with environment variables
- 🚨 **Safety checks** and notifications

## 📁 Project Structure

```
backup-manager/
├── 📄 backups.sh                  # Main backup script
├── ⚙️ config.json                # Configuration
├── 🛠️ setup_systemd.sh           # Auto-start setup
├── 📥 download_rustic.sh          # Binary downloader
├── 🔄 update_rustic.sh           # Version updater
├── 🧰 init_recovery.sh           # Recovery kit preparation
├── 📋 systemd_helper.sh          # Quick systemd commands
├── 🔍 check_environment.sh       # Environment checker
├── 📄 LICENSE                    # MIT License
├── installers/                   # Rustic binaries (extract .tar.gz archives here)
│   ├── rustic-v0.9.5-x86_64-unknown-linux-gnu.tar.gz
│   ├── rustic-v0.9.5-aarch64-unknown-linux-gnu.tar.gz
│   ├── rustic-v0.9.5-x86_64-apple-darwin.tar.gz
│   ├── rustic-v0.9.5-aarch64-apple-darwin.tar.gz
│   ├── rustic-v0.9.5-x86_64-pc-windows-msvc.tar.gz
│   └── rustic-*                  # Extracted binaries (after extraction)
├── recovery-kit/                 # Portable recovery kit
│   ├── recovery.sh              # Unix recovery
│   ├── recovery.bat             # Windows recovery
│   ├── rustic-*                 # Binaries for all platforms
│   └── README.md
└── .credentials/                 # Repository passwords (auto-created at runtime)
```

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone <your-repo>
cd backup-manager
chmod +x *.sh
```

### 2. Download and Extract Rustic

```bash
# Auto-download for all platforms
./download_rustic.sh

# Extract downloaded archives
cd installers/
for archive in *.tar.gz; do
    tar -xzf "$archive"
done
cd ..

# Or manual download of specific versions
wget https://github.com/rustic-rs/rustic/releases/latest/download/rustic-v0.9.5-x86_64-unknown-linux-gnu.tar.gz
tar -xzf rustic-v0.9.5-x86_64-unknown-linux-gnu.tar.gz
```

### 3. Initial Configuration

```bash
# Create default configuration
./backups.sh

# Edit for your needs
nano config.json
```

### 4. First Backup

```bash
./backups.sh backup
```

## ⚙️ Configuration

### Main `config.json` file:

```json
{
  "backup": {
    "source_dirs": [
      "$HOME/.config",
      "$HOME/.ssh",
      "$HOME/projects"
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
      "description": "Local storage"
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
    },
    "ssh_server": {
      "type": "sftp",
      "enabled": false,
      "host": "backup.example.com",
      "port": 22,
      "username": "$USER",
      "path": "/home/$USER/backups/rustic",
      "ssh_key": "$HOME/.ssh/id_rsa",
      "ssh_password": "",
      "description": "SSH Backup Server"
    }
  },
  "multi_repo": {
    "enabled": false,
    "sync_all": true,
    "repositories": ["local", "s3_aws"],
    "require_all_success": false,
    "parallel_uploads": true
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
      "daily_morning": "*-*-* 02:00:00",
      "daily_twice": "*-*-* 02,14:00:00",
      "workdays_only": "Mon..Fri *-*-* 02:00:00",
      "business_hours": "Mon..Fri *-*-* 09,11,13,15,17:00:00",
      "weekly": "Mon *-*-* 03:00:00",
      "monthly": "*-*-01 02:00:00"
    }
  },
  "retention": {
    "keep_daily": 7,
    "keep_weekly": 4,
    "keep_monthly": 6,
    "keep_yearly": 2
  },
  "rustic": {
    "compression": "auto",
    "encryption": "repokey",
    "threads": 4
  }
}
```

## 🗄️ Supported Repositories

### 📂 Local Storage
```json
{
  "type": "local",
  "enabled": true,
  "path": "$HOME/rustic-backup"
}
```

### ☁️ S3-Compatible Storage

**AWS S3:**
```json
{
  "type": "s3",
  "s3_region": "us-east-1",
  "s3_endpoint_url": "",
  "s3_bucket": "my-backup-bucket"
}
```

**MinIO:**
```json
{
  "type": "s3",
  "s3_region": "us-east-1",
  "s3_endpoint_url": "https://minio.example.com",
  "s3_bucket": "backups"
}
```

**Yandex Object Storage:**
```json
{
  "type": "s3",
  "s3_region": "ru-central1",
  "s3_endpoint_url": "https://storage.yandexcloud.net",
  "s3_bucket": "my-backup-bucket"
}
```

### 🔑 S3 Credentials Setup

```bash
# Add to ~/.bashrc:
export AWS_ACCESS_KEY_ID="your_access_key"
export AWS_SECRET_ACCESS_KEY="your_secret_key"

# Reload environment:
source ~/.bashrc
```

### 🔐 SSH/SFTP Servers
```json
{
  "type": "sftp",
  "host": "backup.example.com",
  "port": 22,
  "username": "$USER",
  "path": "/home/$USER/backups/rustic",
  "ssh_key": "$HOME/.ssh/id_rsa"
}
```

## 📋 Usage

### Interactive Menu
```bash
./backups.sh
```

### Command Line
```bash
./backups.sh backup          # Run backup
./backups.sh info            # Show information
./backups.sh restore         # Restore data
./backups.sh check           # Check configuration
```

### Repository Management
```bash
./backups.sh                 # Menu → "Repository Management"
```

## ⏰ Automation

### systemd Setup
```bash
# Install and configure
./setup_systemd.sh install

# Management
./setup_systemd.sh status   # Status
./setup_systemd.sh logs     # Logs
./setup_systemd.sh schedule # Edit schedule
```

### Quick Commands
```bash
./systemd_helper.sh start   # Start now
./systemd_helper.sh status  # Service status
./systemd_helper.sh logs    # Live logs
./systemd_helper.sh next    # Next run
```

### Schedule Examples
- `hourly` - every hour
- `daily_morning` - daily at 02:00
- `daily_twice` - daily at 02:00 and 14:00
- `workdays_only` - weekdays at 02:00
- `business_hours` - weekdays every 2 hours (9-17)
- `weekly` - weekly on Mondays
- `monthly` - monthly on the 1st

## 🆘 Recovery Kit

### Prepare Portable Kit
```bash
./init_recovery.sh
```

### Use Recovery Kit
```bash
# Linux/macOS
cd recovery-kit
./recovery.sh

# Windows
cd recovery-kit
recovery.bat
```

Recovery kit contains:
- 📦 Rustic binaries for all platforms
- 🔧 Autonomous recovery scripts
- 🔑 Repository passwords
- 📖 Usage instructions

## 🔧 Additional Tools

### Environment Check
```bash
./check_environment.sh
```

### Rustic Installation

The script expects extracted rustic binaries in the `installers/` directory. If you have downloaded the archives (.tar.gz files), you need to extract them first:

```bash
# Extract all archives
cd installers/
for archive in *.tar.gz; do
    tar -xzf "$archive"
done
cd ..
```

After extraction, rustic will be automatically installed to `~/.local/bin/` when you first run the backup script.

## 📊 Usage Examples

### Simple Local Backup
```json
{
  "backup": {
    "source_dirs": ["$HOME/Documents", "$HOME/.config"],
    "primary_repo": "local"
  },
  "repositories": {
    "local": {
      "type": "local", 
      "enabled": true,
      "path": "$HOME/backups"
    }
  }
}
```

### Multi-Repository (Local + S3)
```json
{
  "multi_repo": {
    "enabled": true,
    "repositories": ["local", "s3_aws"],
    "parallel_uploads": true
  }
}
```

### Workdays Only
```json
{
  "schedule": {
    "preset": "workdays_only"
  }
}
```

## 🚨 Troubleshooting

### S3 Issues
```bash
# Check environment variables
echo $AWS_ACCESS_KEY_ID
echo $AWS_SECRET_ACCESS_KEY

# Test connection
./backups.sh → "Repository Management" → "Test connections"
```

### SSH Issues
```bash
# Test SSH key
ssh -i ~/.ssh/id_rsa user@host

# Check key permissions
chmod 600 ~/.ssh/id_rsa
```

### systemd Issues
```bash
# Check status
systemctl --user status rustic-backup.timer

# Check logs
journalctl --user -u rustic-backup.service -f

# Restart
systemctl --user restart rustic-backup.timer
```

### Recovery from Errors
```bash
# Check repository integrity
rustic check --repository /path/to/repo --password-file .credentials/repo.password

# Restore from another repository
./backups.sh restore
```

## 📈 Monitoring and Logs

### Log Files
- `~/backup_manager.log` - main logs
- `journalctl --user -u rustic-backup.service` - systemd logs

### Notifications
- 🖥️ Desktop notifications (notify-send)
- 📧 Email notifications (planned)

## 🔒 Security

- 🔐 **Encryption**: AES-256 client-side
- 🔑 **Passwords**: automatic generation and secure storage
- 📂 **Access rights**: restricted access to credential files
- 🛡️ **Checks**: size and checksum validation

## 🔄 Compatibility

- **OS**: Linux, macOS, Windows
- **Architectures**: x86_64, ARM64
- **Formats**: restic compatibility
- **Cloud**: AWS S3, MinIO, Yandex, DigitalOcean Spaces

## 📝 Requirements

### Required
- `bash` >= 4.0
- `jq` - JSON processing
- `gettext-base` (envsubst) - variable substitution

### For S3
- Environment variables: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

### For SSH
- SSH client
- `sshpass` (for passwords, optional)

### Install Dependencies
```bash
# Ubuntu/Debian
sudo apt install jq gettext-base sshpass

# CentOS/RHEL
sudo yum install jq gettext sshpass

# macOS
brew install jq gettext
```

## 📄 License

MIT License - see LICENSE file

## 🙏 Acknowledgments

- [rustic-rs](https://github.com/rustic-rs/rustic) - excellent backup tool

---

**🆘 Support**: Create an issue in the repository for questions and suggestions.
