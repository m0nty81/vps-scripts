#!/usr/bin/env bash

# Библиотека утилит для работы с ОС
# Определение ОС, версии, установка пакетов

set -euo pipefail

# =============================================================================
# Глобальные переменные
# =============================================================================
OS_NAME=""
OS_VERSION=""
OS_ID=""
OS_CODENAME=""

# =============================================================================
# Определение ОС
# =============================================================================

# Определить ОС и версию
detect_os() {
    log_info "Определение операционной системы..."
    
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_CODENAME="${VERSION_CODENAME:-}"
        OS_NAME="$NAME"
        
        log_success "Обнаружена ОС: $OS_NAME $OS_VERSION ($OS_CODENAME)"
    elif [[ -f /etc/lsb-release ]]; then
        # Для старых систем
        # shellcheck source=/dev/null
        source /etc/lsb-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${DISTRIB_RELEASE:-}"
        OS_CODENAME="${DISTRIB_CODENAME:-}"
        OS_NAME="${DISTRIB_DESCRIPTION:-}"
        
        log_success "Обнаружена ОС: $OS_NAME"
    else
        log_error "Не удалось определить операционную систему"
        return 1
    fi
    
    # Проверка поддерживаемых ОС
    if ! is_supported_os; then
        log_warning "ОС может быть не поддерживается: $OS_ID $OS_VERSION"
        log_warning "Поддерживаются: debian (11, 12), ubuntu (20.04, 22.04, 24.04)"
    fi
}

# Проверка поддерживаемой ОС
is_supported_os() {
    case "$OS_ID" in
        debian)
            case "$OS_VERSION" in
                11|12)
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        ubuntu)
            case "$OS_VERSION" in
                20.04|22.04|24.04)
                    return 0
                    ;;
                *)
                    return 1
                    ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# Установка пакетов
# =============================================================================

# Обновить списки пакетов
update_packages() {
    log_info "Обновление списков пакетов..."
    apt update -qq 2>/dev/null || apt update
    log_success "Списки пакетов обновлены"
}

# Обновить установленные пакеты
upgrade_packages() {
    log_info "Обновление установленных пакетов..."
    DEBIAN_FRONTEND=noninteractive apt upgrade -y -qq 2>/dev/null || \
    DEBIAN_FRONTEND=noninteractive apt upgrade -y
    log_success "Пакеты обновлены"
}

# Установить пакеты
install_packages() {
    local packages=("$@")
    local pkg_list="${packages[*]}"
    
    log_info "Установка пакетов: $pkg_list"
    
    DEBIAN_FRONTEND=noninteractive apt install -y -qq 2>/dev/null "${packages[@]}" || \
    DEBIAN_FRONTEND=noninteractive apt install -y "${packages[@]}"
    
    log_success "Пакеты установлены: $pkg_list"
}

# Проверить установлен ли пакет
is_package_installed() {
    local package="$1"
    dpkg -l "$package" >/dev/null 2>&1
}

# Установить пакет если не установлен
ensure_package() {
    local package="$1"
    
    if is_package_installed "$package"; then
        log_info "Пакет уже установлен: $package"
        return 0
    fi
    
    install_packages "$package"
}

# =============================================================================
# Специфичные функции для ОС
# =============================================================================

# Получить команду для группы sudo
get_sudo_group() {
    case "$OS_ID" in
        debian|ubuntu)
            echo "sudo"
            ;;
        *)
            # Пробуем определить
            if getent group sudo >/dev/null 2>&1; then
                echo "sudo"
            elif getent group wheel >/dev/null 2>&1; then
                echo "wheel"
            else
                echo "sudo"  # default
            fi
            ;;
    esac
}

# Перезапустить службу
restart_service() {
    local service="$1"
    
    log_info "Перезапуск службы: $service"
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "$service"
    elif command -v service >/dev/null 2>&1; then
        service "$service" restart
    else
        log_error "Не удалось найти команду для перезапуска служб"
        return 1
    fi
    
    log_success "Служба $service перезапущена"
}

# Включить службу
enable_service() {
    local service="$1"
    
    log_info "Включение службы: $service"
    
    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable "$service" --now
    elif command -v service >/dev/null 2>&1; then
        service "$service" start
    else
        log_error "Не удалось найти команду для включения служб"
        return 1
    fi
    
    log_success "Служба $service включена"
}
