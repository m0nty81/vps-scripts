#!/usr/bin/env bash

# Библиотека для управления rollback
# Запись всех изменений для последующего отката

set -euo pipefail

# =============================================================================
# Глобальные переменные
# =============================================================================
ROLLBACK_ENABLED="false"
ROLLBACK_SCRIPT=""
ROLLBACK_DESC=()  # Массив описаний
ROLLBACK_CMD=()   # Массив команд

# =============================================================================
# Инициализация rollback
# =============================================================================

rollback_init() {
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    ROLLBACK_SCRIPT="/root/rollback-${timestamp}.sh"
    
    ROLLBACK_ENABLED="true"
    
    # Очищаем массивы
    ROLLBACK_DESC=()
    ROLLBACK_CMD=()
    
    log_info "Rollback инициализирован"
}

# Проверка включен ли rollback
is_rollback_enabled() {
    [[ "$ROLLBACK_ENABLED" == "true" ]]
}

# =============================================================================
# Функции записи rollback-действий
# =============================================================================

rollback_add_command() {
    local description="$1"
    local command="$2"
    
    if ! is_rollback_enabled; then
        return 0
    fi
    
    ROLLBACK_DESC+=("$description")
    ROLLBACK_CMD+=("$command")
    
    log_debug "Добавлена rollback команда: $description"
}

rollback_add_file_restore() {
    local description="$1"
    local backup_file="$2"
    local target_file="$3"
    
    if ! is_rollback_enabled; then
        return 0
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_warning "Backup файл не найден: $backup_file"
        return 0
    fi
    
    rollback_add_command "$description" "cp '$backup_file' '$target_file' && chmod 644 '$target_file'"
}

rollback_add_file_remove() {
    local description="$1"
    local file="$2"
    
    if ! is_rollback_enabled; then
        return 0
    fi
    
    rollback_add_command "$description" "rm -f '$file'"
}

rollback_add_user_delete() {
    local description="$1"
    local username="$2"
    
    if ! is_rollback_enabled; then
        return 0
    fi
    
    rollback_add_command "$description" "id '$username' >/dev/null 2>&1 && userdel -r '$username' || true"
}

rollback_add_group_remove() {
    local description="$1"
    local username="$2"
    local group="$3"
    
    if ! is_rollback_enabled; then
        return 0
    fi
    
    rollback_add_command "$description" "gpasswd -d '$username' '$group' 2>/dev/null || true"
}

rollback_add_package_remove() {
    local description="$1"
    local package="$2"
    
    if ! is_rollback_enabled; then
        return 0
    fi
    
    rollback_add_command "$description" "dpkg -l '$package' >/dev/null 2>&1 && apt remove -y '$package' || true"
}

rollback_add_firewall_rule_delete() {
    local description="$1"
    local port="$2"
    local protocol="${3:-tcp}"
    
    if ! is_rollback_enabled; then
        return 0
    fi
    
    rollback_add_command "$description" "ufw status | grep -q '$port/$protocol' && ufw delete allow '$port/$protocol' || true"
}

rollback_add_firewall_disable() {
    local description="$1"
    
    if ! is_rollback_enabled; then
        return 0
    fi
    
    rollback_add_command "$description" "ufw --force disable 2>/dev/null || true"
}

rollback_add_ssh_restore() {
    local description="$1"
    local backup_file="$2"
    
    if ! is_rollback_enabled; then
        return 0
    fi
    
    if [[ -f "$backup_file" ]]; then
        rollback_add_file_restore "$description" "$backup_file" "/etc/ssh/sshd_config"
    else
        log_warning "Backup SSH конфига не найден: $backup_file"
    fi
}

# =============================================================================
# Генерация и выполнение rollback скрипта
# =============================================================================

rollback_generate_script() {
    local script_file="${1:-$ROLLBACK_SCRIPT}"
    
    # Если файл не указан, создаем временный
    if [[ -z "$script_file" ]]; then
        script_file="/tmp/rollback-$(date +%s).sh"
    fi
    
    > "$script_file"
    
    cat >> "$script_file" << 'EOF'
#!/usr/bin/env bash
# Rollback скрипт для VPS Deploy
set -euo pipefail

echo "=== Rollback скрипт ==="
echo "Этот скрипт откатит изменения, сделанные deploy.sh"
echo ""

# Подтверждение для ручного запуска
if [[ -z "${ROLLBACK_AUTO:-}" ]]; then
    read -p "Продолжить? (y/N): " -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Отмена."
        exit 0
    fi
fi

echo "Начинаю откат..."
EOF
    
    # Добавляем команды в обратном порядке
    local i
    for ((i=${#ROLLBACK_DESC[@]}-1; i>=0; i--)); do
        local desc="${ROLLBACK_DESC[i]}"
        local cmd="${ROLLBACK_CMD[i]}"
        cat >> "$script_file" << EOF

# $desc
echo "[ROLLBACK] $desc..."
if ! $cmd; then
    echo "[WARNING] Команда завершилась с ошибкой: $desc"
fi
EOF
    done
    
    cat >> "$script_file" << 'EOF'

echo ""
echo "=== Rollback завершен ==="

# Показываем статус
if command -v ufw >/dev/null 2>&1; then
    echo "Статус firewall:"
    ufw status verbose 2>/dev/null || true
    echo ""
fi

if systemctl list-unit-files 2>/dev/null | grep -q '^ssh.service'; then
    echo "Статус SSH:"
    systemctl status ssh --no-pager 2>/dev/null || true
    echo ""
elif systemctl list-unit-files 2>/dev/null | grep -q '^sshd.service'; then
    echo "Статус SSH:"
    systemctl status sshd --no-pager 2>/dev/null || true
    echo ""
fi
EOF
    
    chmod +x "$script_file"
    echo "$script_file"
}

rollback_finalize() {
    if ! is_rollback_enabled; then
        return 0
    fi
    
    local script
    script=$(rollback_generate_script)
    
    log_info "Rollback скрипт создан: $script"
    log_warning "В случае проблем запустите: bash $script"
}

rollback_on_error() {
    local exit_code=$?
    
    if ! is_rollback_enabled; then
        exit $exit_code
    fi
    
    echo ""
    echo -e "${RED}[ERROR]${NC} Скрипт завершился с ошибкой"
    echo -e "${RED}[ERROR]${NC} Код возврата: $exit_code"
    echo ""
    
    # Генерируем скрипт из текущих массивов (все команды до ошибки)
    local script
    script=$(ROLLBACK_AUTO=1 rollback_generate_script)
    
    echo -e "${YELLOW}Запускаю автоматический rollback...${NC}"
    echo ""
    
    bash "$script"
    
    echo ""
    echo -e "${YELLOW}Rollback завершен. Проверьте систему вручную.${NC}"
    
    exit $exit_code
}
