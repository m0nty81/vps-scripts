# Пример конфигурационного файла
# Скопируйте этот файл в config/config.sh и настройте под свои нужды

# Настройки сервера
SERVER_HOST="your-server.com"
SERVER_USER="root"
SERVER_PORT="22"

# Пути на сервере
REMOTE_APP_DIR="/var/www/app"
REMOTE_BACKUP_DIR="/var/backups"

# Настройки приложения
APP_NAME="my-app"
APP_ENV="production"

# База данных (опционально)
DB_HOST="localhost"
DB_NAME="app_db"
DB_USER="app_user"
# DB_PASS="your_password"  # Рекомендуется использовать .env файл

# Дополнительные параметры
BACKUP_ENABLED=true
BACKUP_RETENTION_DAYS=7