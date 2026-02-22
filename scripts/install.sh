#!/usr/bin/env bash

# VPS Deploy - Установка и запуск через curl
# Использование: curl -sL <url>/install.sh | sudo bash
# Или: curl -sL <url>/install.sh -o install.sh && sudo bash install.sh

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Репозиторий (замените на ваш)
REPO_URL="https://raw.githubusercontent.com/m0nty81/vps-scripts/main"

# Временная директория
TEMP_DIR=$(mktemp -d)

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

cleanup() {
    log_info "Очистка временных файлов..."
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         VPS Deploy Script - Установка                     ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    log_error "Скрипт должен быть запущен от root"
    log_error "Используйте: curl -sL <url>/install.sh | sudo bash"
    exit 1
fi

log_info "Загрузка файлов из репозитория..."

# Загружаем основные файлы
FILES=(
    "bin/deploy.sh"
    "lib/common.sh"
    "lib/os_utils.sh"
    "lib/ssh_utils.sh"
    "lib/user_utils.sh"
    "lib/firewall_utils.sh"
)

for file in "${FILES[@]}"; do
    log_info "Загрузка: $file"
    
    # Создаем директорию если нужно
    dir="$TEMP_DIR/$(dirname "$file")"
    mkdir -p "$dir"
    
    # Загружаем файл
    if curl -sL -o "$TEMP_DIR/$file" "${REPO_URL}/${file}"; then
        log_success "Загружено: $file"
    else
        log_error "Не удалось загрузить: $file"
        exit 1
    fi
done

# Делаем скрипты исполняемыми
chmod +x "$TEMP_DIR/bin/deploy.sh"

echo ""
log_success "Все файлы загружены в: $TEMP_DIR"
echo ""

# Запускаем основной скрипт
log_info "Запуск скрипта настройки..."
echo ""

cd "$TEMP_DIR"
exec ./bin/deploy.sh
