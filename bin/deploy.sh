#!/usr/bin/env bash

# Основной скрипт для базовой настройки VPS
# Debian/Ubuntu: SSH, firewall, пользователи
#
# Использование: sudo ./deploy.sh

set -euo pipefail

# =============================================================================
# Инициализация
# =============================================================================

# Определяем директорию скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
LIB_DIR="${PROJECT_ROOT}/lib"

# Подключаем библиотеки
if [[ -d "$LIB_DIR" ]]; then
    for lib in "$LIB_DIR"/*.sh; do
        if [[ -f "$lib" ]]; then
            # shellcheck source=/dev/null
            source "$lib"
        fi
    done
else
    echo "ERROR: Директория библиотек не найдена: $LIB_DIR"
    exit 1
fi

# =============================================================================
# Глобальные переменные (заполняются в диалоге)
# =============================================================================
CREATE_NEW_USER="false"
NEW_USERNAME=""
SSH_KEY_MODE=""        # "paste" или "generate"
SSH_KEY_TYPE=""        # "ed25519" или "rsa"
SSH_KEY=""             # Вставленный ключ
GENERATED_KEY_FILE=""  # Путь к сгенерированному ключу
SSH_PORT=""
ENABLE_FIREWALL="false"
RUN_UPGRADE="false"

# =============================================================================
# Диалоговый режим
# =============================================================================

show_welcome() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         VPS Deploy Script - Базовая настройка             ║"
    echo "║         Debian/Ubuntu: SSH, Firewall, Users               ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

run_dialog() {
    log_header "Диалог настройки"
    
    echo -e "${YELLOW}Ответьте на вопросы для настройки сервера${NC}"
    echo ""
    
    # Вопрос 1: Обновление системы
    echo -e "${BOLD}[1/6]${NC}"
    if ask_yes_no "Выполнить обновление системы (apt update && apt upgrade)?" "n"; then
        RUN_UPGRADE="true"
    fi
    
    # Вопрос 2: Создание нового пользователя
    echo ""
    echo -e "${BOLD}[2/6]${NC}"
    if ask_yes_no "Создать нового пользователя?" "n"; then
        CREATE_NEW_USER="true"
        
        # Запрашиваем имя пользователя
        echo ""
        echo -e "${CYAN}Введите имя нового пользователя:${NC}"
        while true; do
            echo -ne "${CYAN}Имя пользователя (латиница, 3-32 символа): ${NC}"
            read -r NEW_USERNAME
            
            # Валидация имени пользователя
            if [[ ! "$NEW_USERNAME" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]; then
                echo -e "${YELLOW}Неверный формат. Имя должно начинаться с буквы,"
                echo -e "содержать только латинские буквы, цифры, _ и -${NC}"
                continue
            fi
            
            # Проверка на существование
            if user_exists "$NEW_USERNAME"; then
                echo -e "${YELLOW}Пользователь '$NEW_USERNAME' уже существует${NC}"
                if ask_yes_no "Продолжить с этим пользователем?" "n"; then
                    break
                fi
            else
                break
            fi
        done
        
        log_info "Будет создан пользователь: $NEW_USERNAME"
    fi
    
    # Вопрос 3: Порт SSH
    echo ""
    echo -e "${BOLD}[3/7]${NC}"
    SSH_PORT=$(ask_number "Укажите порт SSH" "22" "1024" "65535")
    log_info "Будет установлен порт SSH: $SSH_PORT"
    
    # Вопрос 4: SSH ключ - выбор режима
    echo ""
    echo -e "${BOLD}[4/7]${NC}"
    echo -e "${CYAN}Настройка SSH ключа${NC}"
    echo ""
    echo "Выберите режим работы с SSH ключом:"
    echo "  1) Вставить существующий публичный ключ"
    echo "  2) Сгенерировать новые ключи на сервере"
    echo ""
    
    while true; do
        echo -ne "${CYAN}Ваш выбор (1-2): ${NC}"
        read -r key_choice
        
        case "$key_choice" in
            1)
                SSH_KEY_MODE="paste"
                SSH_KEY=$(ask_ssh_key "Вставьте публичный ключ")
                if [[ -z "$SSH_KEY" ]]; then
                    log_warning "SSH ключ не указан. Вход по паролю останется включенным!"
                fi
                break
                ;;
            2)
                SSH_KEY_MODE="generate"
                echo ""
                echo -e "${CYAN}Выберите тип ключа:${NC}"
                echo "  1) ed25519 (рекомендуется, современный и безопасный)"
                echo "  2) rsa (совместимость со старыми системами)"
                echo ""
                
                while true; do
                    echo -ne "${CYAN}Ваш выбор (1-2): ${NC}"
                    read -r type_choice
                    
                    case "$type_choice" in
                        1)
                            SSH_KEY_TYPE="ed25519"
                            break
                            ;;
                        2)
                            SSH_KEY_TYPE="rsa"
                            break
                            ;;
                        *)
                            echo -e "${YELLOW}Неверный выбор${NC}"
                            ;;
                    esac
                done
                
                log_info "Будут сгенерированы ключи типа: $SSH_KEY_TYPE"
                break
                ;;
            *)
                echo -e "${YELLOW}Неверный выбор${NC}"
                ;;
        esac
    done
    
    # Определяем для кого ключ
    local key_target
    if [[ "$CREATE_NEW_USER" == "true" ]]; then
        key_target="$NEW_USERNAME"
    else
        key_target="root"
    fi
    log_info "Ключ будет установлен для: $key_target"
    
    # Вопрос 5: Firewall
    echo ""
    echo -e "${BOLD}[5/7]${NC}"
    if ask_yes_no "Включить firewall (UFW)?" "y"; then
        ENABLE_FIREWALL="true"
        log_info "Firewall будет включен для порта $SSH_PORT"
    fi
    
    # Вопрос 6: Подтверждение
    echo ""
    echo -e "${BOLD}[6/7]${NC}"
    echo -e "${CYAN}Проверка параметров:${NC}"
    echo "  • Обновление системы: $RUN_UPGRADE"
    echo "  • Создание пользователя: $CREATE_NEW_USER"
    if [[ "$CREATE_NEW_USER" == "true" ]]; then
        echo "    - Имя: $NEW_USERNAME"
    fi
    echo "  • Порт SSH: $SSH_PORT"
    if [[ "$SSH_KEY_MODE" == "paste" ]]; then
        echo "  • SSH ключ: вставлен вручную"
    elif [[ "$SSH_KEY_MODE" == "generate" ]]; then
        echo "  • SSH ключ: будет сгенерирован ($SSH_KEY_TYPE)"
    else
        echo "  • SSH ключ: не указан"
    fi
    echo "  • Firewall: $ENABLE_FIREWALL"
    echo ""
    
    if ask_yes_no "Применить настройки?" "n"; then
        log_success "Настройки подтверждены"
        return 0
    else
        log_warning "Настройка отменена пользователем"
        return 1
    fi
}

# =============================================================================
# Основные этапы настройки
# =============================================================================

run_system_update() {
    if [[ "$RUN_UPGRADE" != "true" ]]; then
        return 0
    fi
    
    log_header "Обновление системы"
    
    update_packages
    
    if ask_yes_no "Выполнить upgrade установленных пакетов?" "n"; then
        upgrade_packages
    fi
    
    log_success "Обновление системы завершено"
}

run_user_setup() {
    if [[ "$CREATE_NEW_USER" != "true" ]]; then
        return 0
    fi

    log_header "Настройка пользователя"

    # Устанавливаем sudo
    ensure_sudo
    
    # Если режим генерации ключей - сначала генерируем
    if [[ "$SSH_KEY_MODE" == "generate" ]]; then
        setup_ssh_dir "$NEW_USERNAME"
        GENERATED_KEY_FILE=$(generate_ssh_keys "$NEW_USERNAME" "$SSH_KEY_TYPE")
        
        # Получаем публичный ключ для добавления в authorized_keys
        SSH_KEY=$(get_public_key "$GENERATED_KEY_FILE")
    fi

    # Создаем пользователя и настраиваем
    setup_user "$NEW_USERNAME" "$SSH_KEY" "true"
    
    # Если ключи сгенерированы - показываем приватный ключ
    if [[ "$SSH_KEY_MODE" == "generate" && -n "$GENERATED_KEY_FILE" ]]; then
        show_private_key "$NEW_USERNAME" "$GENERATED_KEY_FILE"
    fi

    log_success "Пользователь $NEW_USERNAME настроен"
}

run_root_ssh_key() {
    # Если не создаем нового пользователя, но ключ указан - ставим для root
    local key_target="root"
    
    if [[ "$CREATE_NEW_USER" != "true" ]]; then
        log_header "Настройка SSH ключа для root"
        
        # Если режим генерации ключей - сначала генерируем
        if [[ "$SSH_KEY_MODE" == "generate" ]]; then
            setup_ssh_dir "$key_target"
            GENERATED_KEY_FILE=$(generate_ssh_keys "$key_target" "$SSH_KEY_TYPE")
            
            # Получаем публичный ключ для добавления в authorized_keys
            SSH_KEY=$(get_public_key "$GENERATED_KEY_FILE")
        fi
        
        if [[ -n "$SSH_KEY" ]]; then
            setup_ssh_dir "$key_target"
            add_ssh_key "$key_target" "$SSH_KEY"
            
            log_success "SSH ключ установлен для root"
            
            # Если ключи сгенерированы - показываем приватный ключ
            if [[ "$SSH_KEY_MODE" == "generate" && -n "$GENERATED_KEY_FILE" ]]; then
                show_private_key "$key_target" "$GENERATED_KEY_FILE"
            fi
        fi
    fi
}

# Показать приватный ключ для копирования
show_private_key() {
    local username="$1"
    local key_file="$2"
    
    log_header "Приватный SSH ключ"
    
    echo -e "${YELLOW}⚠️  ВАЖНО: Сохраните этот ключ! ⚠️${NC}"
    echo ""
    echo "Приватный ключ для подключения к серверу:"
    echo ""
    echo -e "${RED}─────────────────────────────────────────${NC}"
    get_private_key "$key_file"
    echo -e "${RED}─────────────────────────────────────────${NC}"
    echo ""
    echo -e "${YELLOW}Инструкция:${NC}"
    echo "  1. Скопируйте ключ выше (включая строки BEGIN/END)"
    echo "  2. Сохраните в файл на локальной машине:"
    echo "     ~/.ssh/vps_${username}"
    echo "  3. Установите правильные права:"
    echo "     chmod 600 ~/.ssh/vps_${username}"
    echo "  4. Подключайтесь командой:"
    echo "     ssh -i ~/.ssh/vps_${username} -p $SSH_PORT ${username}@<server-ip>"
    echo ""
    
    # Предлагаем подтвердить что ключ сохранен
    if ask_yes_no "Вы сохранили приватный ключ?" "y"; then
        log_success "Приватный ключ сохранен пользователем"
    else
        log_warning "Пользователь не подтвердил сохранение ключа"
    fi
}

run_ssh_config() {
    log_header "Настройка SSH"
    
    # Определяем значение PermitRootLogin
    local permit_root="no"
    if [[ "$CREATE_NEW_USER" != "true" ]]; then
        # Если не создаем нового пользователя, оставляем доступ для root
        # но только по ключу
        permit_root="prohibit-password"
        log_info "PermitRootLogin установлен в 'prohibit-password' (только по ключу)"
    fi
    
    configure_ssh "$SSH_PORT" "$permit_root" "no" "yes"
    
    log_success "Конфигурация SSH применена"
}

run_firewall_setup() {
    if [[ "$ENABLE_FIREWALL" != "true" ]]; then
        log_info "Firewall не включен (настроено только правило для SSH)"
        return 0
    fi
    
    setup_firewall "$SSH_PORT" "true"
    
    log_success "Firewall настроен и включен"
}

run_ssh_restart() {
    log_header "Перезапуск SSH"
    
    echo -e "${YELLOW}⚠️  ВНИМАНИЕ ⚠️${NC}"
    echo ""
    echo "Сейчас служба SSH будет перезапущена."
    echo ""
    echo "После перезапуска:"
    echo "  1. Не закрывайте текущую сессию SSH"
    echo "  2. Откройте НОВОЕ подключение на порту $SSH_PORT"
    echo "  3. Убедитесь что подключение работает"
    echo "  4. Только после этого закрывайте старую сессию"
    echo ""
    
    if ask_yes_no "Продолжить перезапуск SSH?" "y"; then
        restart_ssh
        log_success "SSH перезапущен"
    else
        log_warning "Перезапуск SSH отменен"
        log_warning "Не забудьте перезапустить SSH вручную: systemctl restart ssh"
    fi
}

show_final_info() {
    log_header "Завершение"
    
    echo -e "${GREEN}✓ Настройка VPS завершена!${NC}"
    echo ""
    echo "Параметры:"
    echo "  • Порт SSH: $SSH_PORT"
    if [[ "$CREATE_NEW_USER" == "true" ]]; then
        echo "  • Пользователь: $NEW_USERNAME (с sudo правами)"
    fi
    echo "  • Firewall: $ENABLE_FIREWALL"
    echo ""
    echo "Важно:"
    echo "  • Для подключения используйте: ssh -p $SSH_PORT user@server"
    echo "  • Лог настройки: $LOG_FILE"
    echo ""
    
    if [[ "$ENABLE_FIREWALL" == "true" ]]; then
        show_ufw_status
    fi
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    # Проверка прав root
    check_root
    
    # Инициализация логирования
    init_logging
    
    log_to_file "===== Запуск скрипта ====="
    
    # Определение ОС
    detect_os
    
    # Показываем приветствие
    show_welcome
    
    # Запускаем диалог
    if ! run_dialog; then
        log_warning "Настройка отменена"
        exit 0
    fi
    
    # Выполняем настройку
    run_system_update
    run_user_setup
    run_root_ssh_key
    run_ssh_config
    run_firewall_setup
    run_ssh_restart
    
    # Финальная информация
    show_final_info
    
    log_to_file "===== Скрипт завершен ====="
    
    echo ""
    log_success "Все этапы выполнены!"
}

# Запуск
main "$@"
