#!/usr/bin/env bash

# Библиотека утилит для управления пользователями
# Создание пользователей, управление sudo, SSH ключами

set -euo pipefail

# =============================================================================
# Создание и управление пользователями
# =============================================================================

# Проверить существование пользователя
user_exists() {
    local username="$1"
    id "$username" >/dev/null 2>&1
}

# Создать нового пользователя
create_user() {
    local username="$1"
    
    if user_exists "$username"; then
        log_warning "Пользователь уже существует: $username"
        return 0
    fi
    
    log_info "Создание пользователя: $username"
    
    # Создаем пользователя без интерактивного запроса пароля
    # adduser сам создаст домашнюю директорию
    adduser --disabled-password --gecos "" "$username"
    
    if user_exists "$username"; then
        log_success "Пользователь создан: $username"
        return 0
    else
        log_error "Не удалось создать пользователя: $username"
        return 1
    fi
}

# Добавить пользователя в группу sudo
add_to_sudo() {
    local username="$1"
    local sudo_group
    
    sudo_group=$(get_sudo_group)
    
    log_info "Добавление пользователя $username в группу $sudo_group"
    
    usermod -aG "$sudo_group" "$username"
    
    # Проверяем что пользователь в группе
    if groups "$username" | grep -q "$sudo_group"; then
        log_success "Пользователь $username добавлен в группу $sudo_group"
        return 0
    else
        log_error "Не удалось добавить пользователя в группу $sudo_group"
        return 1
    fi
}

# Установить sudo если не установлен
ensure_sudo() {
    log_info "Проверка наличия sudo..."
    
    if ! command_exists sudo; then
        log_info "Установка sudo..."
        install_packages sudo
    fi
    
    log_success "sudo установлен"
}

# =============================================================================
# SSH ключи для пользователей
# =============================================================================

# Настроить SSH директорию для пользователя
setup_ssh_dir() {
    local username="$1"
    local home_dir
    
    # Получаем домашнюю директорию
    home_dir=$(eval echo "~$username")
    
    if [[ ! -d "$home_dir" ]]; then
        log_error "Домашняя директория не найдена: $home_dir"
        return 1
    fi
    
    local ssh_dir="$home_dir/.ssh"
    
    log_info "Настройка SSH директории для $username"
    
    # Создаем .ssh если не существует
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        log_info "Создана директория: $ssh_dir"
    fi
    
    # Устанавливаем правильные права
    chmod 700 "$ssh_dir"
    chown "$username:$username" "$ssh_dir"
    
    log_success "SSH директория настроена для $username"
}

# Добавить SSH ключ пользователю
add_ssh_key() {
    local username="$1"
    local ssh_key="$2"
    local home_dir
    local authorized_keys
    
    if [[ -z "$ssh_key" ]]; then
        log_warning "SSH ключ пустой, пропускаем"
        return 0
    fi
    
    home_dir=$(eval echo "~$username")
    authorized_keys="$home_dir/.ssh/authorized_keys"
    
    log_info "Добавление SSH ключа для $username"
    
    # Создаем backup существующего файла
    if [[ -f "$authorized_keys" ]]; then
        backup_file "$authorized_keys"
    fi
    
    # Добавляем ключ (проверяем что не дубликат)
    if grep -qF "$ssh_key" "$authorized_keys" 2>/dev/null; then
        log_info "Ключ уже существует в authorized_keys"
    else
        echo "$ssh_key" >> "$authorized_keys"
        log_success "SSH ключ добавлен"
    fi
    
    # Устанавливаем права
    chmod 600 "$authorized_keys"
    chown "$username:$username" "$authorized_keys"
    
    log_success "SSH ключ настроен для $username"
}

# Установить пароль для пользователя
set_user_password() {
    local username="$1"
    local password="$2"
    
    log_info "Установка пароля для пользователя $username"
    
    # Устанавливаем пароль через chpasswd
    echo "$username:$password" | chpasswd
    
    if [[ $? -eq 0 ]]; then
        log_success "Пароль установлен для $username"
        return 0
    else
        log_error "Не удалось установить пароль для $username"
        return 1
    fi
}

# =============================================================================
# Комплексная настройка пользователя
# =============================================================================

# Настроить пользователя "под ключ"
setup_user() {
    local username="$1"
    local ssh_key="${2:-}"
    local add_sudo="${3:-true}"
    local password="${4:-}"
    
    log_header "Настройка пользователя: $username"
    
    # Создаем если не существует
    if ! user_exists "$username"; then
        create_user "$username"
    fi
    
    # Добавляем в sudo если нужно
    if [[ "$add_sudo" == "true" ]]; then
        ensure_sudo
        add_to_sudo "$username"
    fi
    
    # Настраиваем SSH
    setup_ssh_dir "$username"
    
    # Добавляем ключ если указан
    if [[ -n "$ssh_key" ]]; then
        add_ssh_key "$username" "$ssh_key"
    fi
    
    # Устанавливаем пароль если указан
    if [[ -n "$password" ]]; then
        set_user_password "$username" "$password"
    fi
    
    log_success "Пользователь $username полностью настроен"
}
