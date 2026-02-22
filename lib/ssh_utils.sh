#!/usr/bin/env bash

# Библиотека утилит для настройки SSH
# Конфигурация sshd, перезапуск службы

set -euo pipefail

# =============================================================================
# Глобальные переменные
# =============================================================================
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_BACKUP=""

# =============================================================================
# Конфигурация SSH
# =============================================================================

# Создать backup конфига SSH
backup_ssh_config() {
    if [[ -f "$SSHD_CONFIG" ]]; then
        SSHD_CONFIG_BACKUP=$(backup_file "$SSHD_CONFIG")
        log_success "Создан backup SSH конфига: $SSHD_CONFIG_BACKUP"
    fi
}

# Изменить параметр в конфиге SSH
# Если параметр существует - обновить, если нет - добавить
set_ssh_option() {
    local option="$1"
    local value="$2"
    local config_file="${3:-$SSHD_CONFIG}"
    
    if [[ ! -f "$config_file" ]]; then
        log_error "Файл конфигурации не найден: $config_file"
        return 1
    fi
    
    log_info "Настройка SSH: $option = $value"
    
    # Проверяем есть ли уже такая опция в конфиге
    if grep -qE "^[[:space:]]*#?[[:space:]]*$option" "$config_file"; then
        # Опция существует (закомментирована или нет) - обновляем
        # Сначала раскомментируем и устанавливаем значение
        sed -i "s/^[[:space:]]*#*[[:space:]]*$option.*/$option $value/" "$config_file"
        log_info "Обновлена опция: $option"
    else
        # Опции нет - добавляем в конец
        echo "$option $value" >> "$config_file"
        log_info "Добавлена опция: $option"
    fi
}

# Настроить SSH согласно требованиям
configure_ssh() {
    local ssh_port="$1"
    local permit_root="${2:-no}"
    local password_auth="${3:-no}"
    local pubkey_auth="${4:-yes}"
    
    log_header "Настройка SSH"
    
    # Создаем backup перед изменениями
    backup_ssh_config
    
    log_info "Применение настроек SSH..."
    
    # Порт SSH
    set_ssh_option "Port" "$ssh_port"
    
    # Запрет входа для root
    set_ssh_option "PermitRootLogin" "$permit_root"
    
    # Отключение парольной аутентификации
    set_ssh_option "PasswordAuthentication" "$password_auth"
    
    # Включение аутентификации по ключу
    set_ssh_option "PubkeyAuthentication" "$pubkey_auth"
    
    # Дополнительные настройки безопасности
    set_ssh_option "MaxAuthTries" "3"
    set_ssh_option "X11Forwarding" "no"
    set_ssh_option "PrintMotd" "no"
    set_ssh_option "AcceptEnv" "LANG LC_*"
    
    log_success "Настройки SSH применены"
    
    # Проверяем синтаксис конфига
    if command -v sshd >/dev/null 2>&1; then
        log_info "Проверка синтаксиса SSH конфигурации..."
        if sshd -t 2>/dev/null; then
            log_success "Конфигурация SSH валидна"
        else
            log_warning "Возможные проблемы в конфигурации SSH"
            if [[ -n "$SSHD_CONFIG_BACKUP" && -f "$SSHD_CONFIG_BACKUP" ]]; then
                log_warning "При проблемах восстановите из: $SSHD_CONFIG_BACKUP"
            fi
        fi
    fi
}

# Перезапустить SSH службу
restart_ssh() {
    log_header "Перезапуск SSH службы"
    
    log_warning "Внимание: после перезапуска SSH убедитесь что:"
    log_warning "  - Открыт новый порт SSH в firewall"
    log_warning "  - У вас есть доступ по SSH ключу"
    log_warning "  - Не закрывайте текущую сессию пока не проверите подключение"
    
    # Проверяем какая служба используется
    local ssh_service="ssh"
    
    # На некоторых системах служба называется sshd
    if ! systemctl list-unit-files | grep -q "^ssh.service"; then
        if systemctl list-unit-files | grep -q "^sshd.service"; then
            ssh_service="sshd"
        fi
    fi
    
    log_info "Перезапуск службы: $ssh_service"
    
    # Тестовая проверка конфигурации перед перезапуском
    if command -v sshd >/dev/null 2>&1; then
        if ! sshd -t 2>/dev/null; then
            log_error "Ошибка в конфигурации SSH. Перезапуск отменен!"
            return 1
        fi
    fi
    
    restart_service "$ssh_service"
    
    log_success "SSH служба перезапущена"
    log_info "Новый порт SSH: $(grep -E "^Port" "$SSHD_CONFIG" | head -1 | awk '{print $2}')"
}

# Проверка состояния SSH службы
check_ssh_status() {
    local ssh_service="ssh"
    
    if systemctl list-unit-files 2>/dev/null | grep -q "^sshd.service"; then
        ssh_service="sshd"
    fi
    
    log_info "Статус службы SSH:"
    systemctl status "$ssh_service" --no-pager 2>/dev/null || \
    service "$ssh_service" status 2>/dev/null || \
    log_warning "Не удалось получить статус службы"
}

# =============================================================================
# Генерация SSH ключей
# =============================================================================

# Сгенерировать SSH ключи
generate_ssh_keys() {
    local username="$1"
    local key_type="${2:-ed25519}"
    local key_size="${3:-}"
    local home_dir
    local ssh_dir
    local key_file
    
    home_dir=$(eval echo "~$username")
    ssh_dir="$home_dir/.ssh"
    key_file="$ssh_dir/id_$key_type"
    
    log_info "Генерация SSH ключей ($key_type) для $username"
    
    # Создаем .ssh если не существует
    if [[ ! -d "$ssh_dir" ]]; then
        mkdir -p "$ssh_dir"
        chmod 700 "$ssh_dir"
        chown "$username:$username" "$ssh_dir"
    fi
    
    # Параметры генерации
    local keygen_opts=("-t" "$key_type" "-f" "$key_file" "-N" "" "-C" "$username@vps-deploy")
    
    # Для RSA добавляем размер ключа
    if [[ "$key_type" == "rsa" ]]; then
        keygen_opts+=("-b" "${key_size:-4096}")
    fi
    
    # Генерируем ключи
    if ssh-keygen "${keygen_opts[@]}"; then
        log_success "SSH ключи сгенерированы"
        
        # Устанавливаем права
        chmod 600 "$key_file"
        chmod 644 "${key_file}.pub"
        chown "$username:$username" "$key_file" "${key_file}.pub"
        
        # Возвращаем пути к ключам
        echo "$key_file"
        return 0
    else
        log_error "Не удалось сгенерировать SSH ключи"
        return 1
    fi
}

# Получить приватный ключ для отображения
get_private_key() {
    local key_file="$1"
    
    if [[ -f "$key_file" ]]; then
        cat "$key_file"
    else
        log_error "Приватный ключ не найден: $key_file"
        return 1
    fi
}

# Получить публичный ключ для отображения
get_public_key() {
    local key_file="$1"
    
    if [[ -f "${key_file}.pub" ]]; then
        cat "${key_file}.pub"
    else
        log_error "Публичный ключ не найден: ${key_file}.pub"
        return 1
    fi
}
