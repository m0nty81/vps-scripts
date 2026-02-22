#!/usr/bin/env bash

# Библиотека общих функций для bash скриптов
# Предоставляет: логирование, диалоги, валидацию

set -euo pipefail

# =============================================================================
# Цвета для вывода
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# =============================================================================
# Логирование
# =============================================================================
LOG_FILE="/var/log/vps-deploy.log"

# Инициализация логирования
init_logging() {
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE" 2>/dev/null || true
    fi
}

# Логирование в файл и консоль
log_to_file() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} $msg"
    log_to_file "INFO: $msg"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $msg"
    log_to_file "SUCCESS: $msg"
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}[WARNING]${NC} $msg"
    log_to_file "WARNING: $msg"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} $msg" >&2
    log_to_file "ERROR: $msg"
}

log_header() {
    local msg="$1"
    echo ""
    echo -e "${BOLD}${CYAN}=== $msg ===${NC}"
    log_to_file "===== $msg ====="
}

# =============================================================================
# Проверка успешности команд
# =============================================================================

# Выполнить команду с проверкой
run_command() {
    local cmd="$1"
    local description="${2:-Выполнение команды}"
    
    log_info "$description..."
    
    if eval "$cmd"; then
        log_success "$description выполнено"
        return 0
    else
        log_error "$description не удалось"
        return 1
    fi
}

# Проверка существования команды
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# =============================================================================
# Диалоговые функции
# =============================================================================

# Запрос подтверждения (y/n)
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"  # y или n
    local response
    
    while true; do
        local default_prompt
        if [[ "$default" == "y" ]]; then
            default_prompt="[Y/n]"
        else
            default_prompt="[y/N]"
        fi
        
        echo -ne "${CYAN}$question $default_prompt: ${NC}"
        read -r response
        
        # Если пустой ввод, используем default
        if [[ -z "$response" ]]; then
            response="$default"
        fi
        
        case "$response" in
            [Yy]|[Yy][Ee][Ss])
                return 0
                ;;
            [Nn]|[Nn][Oo])
                return 1
                ;;
            *)
                echo -e "${YELLOW}Пожалуйста, введите 'y' или 'n'${NC}"
                ;;
        esac
    done
}

# Запрос строки с опциональным значением по умолчанию
ask_string() {
    local question="$1"
    local default="${2:-}"
    local response
    
    while true; do
        local prompt
        if [[ -n "$default" ]]; then
            prompt="${question} [default: $default]: "
        else
            prompt="${question}: "
        fi
        
        echo -ne "${CYAN}$prompt${NC}"
        read -r response
        
        if [[ -z "$response" && -n "$default" ]]; then
            echo "$default"
            return 0
        elif [[ -z "$response" ]]; then
            echo -e "${YELLOW}Это поле обязательно для заполнения${NC}"
            continue
        fi
        
        echo "$response"
        return 0
    done
}

# Запрос числа в диапазоне
ask_number() {
    local question="$1"
    local default="${2:-}"
    local min="${3:-1}"
    local max="${4:-65535}"
    local response
    
    while true; do
        local prompt
        if [[ -n "$default" ]]; then
            prompt="${question} (default: $default, диапазон: $min-$max): "
        else
            prompt="${question} (диапазон: $min-$max): "
        fi
        
        echo -ne "${CYAN}$prompt${NC}"
        read -r response
        
        # Если пустой ввод и есть default
        if [[ -z "$response" ]]; then
            if [[ -n "$default" ]]; then
                # Проверяем что default в диапазоне
                if [[ "$default" =~ ^[0-9]+$ ]] && \
                   [[ "$default" -ge "$min" ]] && \
                   [[ "$default" -le "$max" ]]; then
                    echo "$default"
                    return 0
                fi
            fi
            echo -e "${YELLOW}Введите число от $min до $max${NC}"
            continue
        fi
        
        # Проверяем что ввод число
        if ! [[ "$response" =~ ^[0-9]+$ ]]; then
            echo -e "${YELLOW}Пожалуйста, введите число${NC}"
            continue
        fi
        
        # Проверяем диапазон
        if [[ "$response" -lt "$min" ]] || [[ "$response" -gt "$max" ]]; then
            echo -e "${YELLOW}Число должно быть от $min до $max${NC}"
            continue
        fi
        
        echo "$response"
        return 0
    done
}

# Запрос SSH ключа (многострочный ввод)
ask_ssh_key() {
    local question="$1"
    local response
    
    echo -e "${CYAN}$question${NC}"
    echo -e "${YELLOW}Вставьте содержимое публичного ключа (например, ~/.ssh/id_ed25519.pub)${NC}"
    echo -e "${YELLOW}Для пропуска введите пустую строку и нажмите Enter${NC}"
    echo -ne "${CYAN}SSH ключ: ${NC}"
    read -r response
    
    # Проверяем формат ключа (должен начинаться с ssh- или ecdsa-)
    if [[ -z "$response" ]]; then
        echo ""
        return 0
    elif [[ "$response" =~ ^(ssh-rsa|ssh-ed25519|ssh-dss|ecdsa-sh2-nistp256|ecdsa-sh2-nistp384|ecdsa-sh2-nistp521)[[:space:]] ]]; then
        echo "$response"
        return 0
    else
        echo -e "${YELLOW}Неверный формат ключа. Ожидается формат OpenSSH${NC}"
        ask_ssh_key "$question"
    fi
}

# =============================================================================
# Утилиты
# =============================================================================

# Создание директории
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_info "Создана директория: $dir"
    fi
}

# Создание backup файла
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.backup.$(date '+%Y%m%d_%H%M%S')"
        cp "$file" "$backup"
        log_info "Создан backup: $backup"
        echo "$backup"
    fi
}

# Проверка запуска от root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Скрипт должен быть запущен от root"
        log_error "Используйте: sudo $0"
        exit 1
    fi
}
