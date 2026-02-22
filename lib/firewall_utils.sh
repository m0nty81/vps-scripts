#!/usr/bin/env bash

# Библиотека утилит для настройки firewall (UFW)
# Установка, конфигурация, управление правилами

set -euo pipefail

# =============================================================================
# Установка и проверка UFW
# =============================================================================

# Проверить установлен ли UFW
is_ufw_installed() {
    command_exists ufw
}

# Установить UFW
install_ufw() {
    log_header "Установка UFW"
    
    if is_ufw_installed; then
        log_info "UFW уже установлен"
        return 0
    fi
    
    log_info "Установка UFW..."
    install_packages ufw
    
    if is_ufw_installed; then
        log_success "UFW установлен"
        return 0
    else
        log_error "Не удалось установить UFW"
        return 1
    fi
}

# =============================================================================
# Настройка правил firewall
# =============================================================================

# Разрешить порт
allow_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    log_info "Разрешение порта $port/$protocol..."
    
    ufw allow "$port/$protocol"
    
    log_success "Порт $port/$protocol разрешен"
}

# Запретить порт
deny_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    log_info "Запрет порта $port/$protocol..."
    
    ufw deny "$port/$protocol"
    
    log_success "Порт $port/$protocol запрещен"
}

# Удалить правило для порта
delete_port_rule() {
    local port="$1"
    local protocol="${2:-tcp}"
    
    log_info "Удаление правила для порта $port/$protocol..."
    
    ufw delete allow "$port/$protocol" 2>/dev/null || true
    
    log_success "Правило для порта $port удалено"
}

# Сбросить все правила UFW
reset_ufw() {
    log_info "Сброс правил UFW..."
    
    ufw --force reset
    
    log_success "Правила UFW сброшены"
}

# =============================================================================
# Комплексная настройка firewall
# =============================================================================

# Настроить firewall для SSH
configure_firewall_ssh() {
    local ssh_port="$1"
    
    log_header "Настройка firewall для SSH"
    
    # Разрешаем новый порт SSH
    allow_port "$ssh_port" "tcp"
    
    log_success "Firewall настроен для SSH на порту $ssh_port"
}

# Включить UFW
enable_ufw() {
    log_header "Включение UFW"
    
    log_warning "Внимание: после включения firewall убедитесь что:"
    log_warning "  - Порт SSH разрешен в firewall"
    log_warning "  - У вас есть активная сессия SSH"
    log_warning "  - Не закрывайте сессию пока не проверите подключение"
    
    # Проверяем что порт SSH разрешен
    local current_ssh_port
    current_ssh_port=$(grep -E "^Port" /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
    current_ssh_port="${current_ssh_port:-22}"
    
    log_info "Текущий порт SSH: $current_ssh_port"
    
    # Включаем UFW в фоновом режиме (force для non-interactive)
    echo "y" | ufw enable
    
    if ufw status | grep -q "Status: active"; then
        log_success "UFW включен"
        
        # Показываем статус
        log_info "Статус firewall:"
        ufw status verbose
    else
        log_error "Не удалось включить UFW"
        return 1
    fi
}

# Выключить UFW
disable_ufw() {
    log_header "Выключение UFW"
    
    if ! is_ufw_installed; then
        log_info "UFW не установлен"
        return 0
    fi
    
    ufw --force disable
    
    if ufw status | grep -q "Status: inactive"; then
        log_success "UFW выключен"
    else
        log_warning "Не удалось выключить UFW"
    fi
}

# Показать статус firewall
show_ufw_status() {
    log_header "Статус firewall"
    
    if ! is_ufw_installed; then
        log_info "UFW не установлен"
        return 0
    fi
    
    ufw status verbose
}

# =============================================================================
# Полная настройка firewall
# =============================================================================

# Настроить firewall "под ключ"
setup_firewall() {
    local ssh_port="$1"
    local enable_firewall="${2:-true}"
    
    log_header "Настройка firewall"
    
    # Устанавливаем UFW
    install_ufw
    
    # Настраиваем правила для SSH
    configure_firewall_ssh "$ssh_port"
    
    # Включаем firewall если нужно
    if [[ "$enable_firewall" == "true" ]]; then
        enable_ufw
    else
        log_info "Firewall не включен (только правила настроены)"
        show_ufw_status
    fi
    
    log_success "Настройка firewall завершена"
}
