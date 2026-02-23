#!/usr/bin/env bash

# Основной скрипт для базовой настройки VPS
# Debian/Ubuntu: SSH, firewall, пользователи
#
# Использование: sudo ./deploy.sh

set -euo pipefail

# =============================================================================
# Инициализация
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
LIB_DIR="${PROJECT_ROOT}/lib"

# Подключаем библиотеки
if [[ -d "$LIB_DIR" ]]; then
    for lib in "$LIB_DIR"/*.sh; do
        if [[ -f "$lib" ]]; then
            source "$lib"
        fi
    done
else
    echo "ERROR: Директория библиотек не найдена: $LIB_DIR"
    exit 1
fi

# =============================================================================
# Глобальные переменные
# =============================================================================
CREATE_NEW_USER="false"
NEW_USERNAME=""
USER_AUTH_METHOD=""    # "key" или "password"
USER_PASSWORD=""
SSH_KEY_MODE=""        # "paste" или "generate"
SSH_KEY_TYPE=""        # "ed25519" или "rsa"
SSH_KEY=""
GENERATED_KEY_FILE=""
SSH_PORT=""
ENABLE_FIREWALL="false"
RUN_UPGRADE="false"

# =============================================================================
# Диалог
# =============================================================================

show_welcome() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         VPS Deploy Script - Базовая настройка             ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

run_dialog() {
    log_header "Диалог настройки"

    echo -e "${YELLOW}Ответьте на вопросы для настройки сервера${NC}"
    echo ""

    # Вопрос 1: Обновление
    echo -e "${BOLD}[1/5]${NC}"
    echo -e "${CYAN}Примечание: apt update будет выполнен всегда${NC}"
    if ask_yes_no "Выполнить upgrade установленных пакетов?" "n"; then
        RUN_UPGRADE="true"
    fi

    # Вопрос 2: Пользователь
    echo ""
    echo -e "${BOLD}[2/5]${NC}"
    if ask_yes_no "Создать нового пользователя?" "n"; then
        CREATE_NEW_USER="true"
        echo ""
        echo -e "${CYAN}Введите имя нового пользователя:${NC}"
        while true; do
            echo -ne "${CYAN}Имя пользователя (латиница, 3-32 символа): ${NC}"
            read -r NEW_USERNAME

            if [[ ! "$NEW_USERNAME" =~ ^[a-z][a-z0-9_-]{2,31}$ ]]; then
                echo -e "${YELLOW}Неверный формат${NC}"
                continue
            fi

            if user_exists "$NEW_USERNAME"; then
                echo -e "${YELLOW}Пользователь уже существует${NC}"
                if ask_yes_no "Продолжить?" "n"; then
                    break
                fi
            else
                break
            fi
        done

        # Метод аутентификации
        echo ""
        echo -e "${BOLD}[2.1/5]${NC}"
        echo "  1) SSH ключ (рекомендуется)"
        echo "  2) Пароль"
        while true; do
            echo -ne "${CYAN}Ваш выбор (1-2): ${NC}"
            read -r auth_choice
            case "$auth_choice" in
                1) USER_AUTH_METHOD="key"; break ;;
                2) USER_AUTH_METHOD="password"; break ;;
                *) echo -e "${YELLOW}Неверный выбор${NC}" ;;
            esac
        done

        # SSH ключ
        if [[ "$USER_AUTH_METHOD" == "key" ]]; then
            echo ""
            echo -e "${BOLD}[2.2/5]${NC}"
            echo "  1) Вставить существующий ключ"
            echo "  2) Сгенерировать новые ключи"
            while true; do
                echo -ne "${CYAN}Ваш выбор (1-2): ${NC}"
                read -r key_choice
                case "$key_choice" in
                    1)
                        SSH_KEY_MODE="paste"
                        SSH_KEY=$(ask_ssh_key "Вставьте публичный ключ")
                        break
                        ;;
                    2)
                        SSH_KEY_MODE="generate"
                        echo ""
                        echo "  1) ed25519 (рекомендуется)"
                        echo "  2) rsa"
                        while true; do
                            echo -ne "${CYAN}Ваш выбор (1-2): ${NC}"
                            read -r type_choice
                            case "$type_choice" in
                                1) SSH_KEY_TYPE="ed25519"; break ;;
                                2) SSH_KEY_TYPE="rsa"; break ;;
                                *) echo -e "${YELLOW}Неверный выбор${NC}" ;;
                            esac
                        done
                        break
                        ;;
                    *) echo -e "${YELLOW}Неверный выбор${NC}" ;;
                esac
            done
        fi

        # Пароль
        echo ""
        echo -e "${BOLD}[2.3/5]${NC}"
        while true; do
            echo -ne "${CYAN}Введите пароль: ${NC}"
            read -r -s USER_PASSWORD
            echo ""
            echo -ne "${CYAN}Подтвердите пароль: ${NC}"
            read -r -s USER_PASSWORD_CONFIRM
            echo ""
            if [[ "$USER_PASSWORD" == "$USER_PASSWORD_CONFIRM" && -n "$USER_PASSWORD" ]]; then
                break
            fi
            echo -e "${YELLOW}Пароли не совпадают${NC}"
        done
    else
        # Если не создаем пользователя, спрашиваем про SSH ключ для root
        echo ""
        echo -e "${BOLD}[2.1/5]${NC}"
        echo "Настроить SSH ключ для root?"
        if ask_yes_no "  1) Вставить существующий ключ" "n"; then
            SSH_KEY_MODE="paste"
            SSH_KEY=$(ask_ssh_key "Вставьте публичный ключ")
        elif ask_yes_no "  2) Сгенерировать новые ключи" "n"; then
            SSH_KEY_MODE="generate"
            echo ""
            echo "  1) ed25519 (рекомендуется)"
            echo "  2) rsa"
            while true; do
                echo -ne "${CYAN}Ваш выбор (1-2): ${NC}"
                read -r type_choice
                case "$type_choice" in
                    1) SSH_KEY_TYPE="ed25519"; break ;;
                    2) SSH_KEY_TYPE="rsa"; break ;;
                    *) echo -e "${YELLOW}Неверный выбор${NC}" ;;
                esac
            done
        fi
    fi

    # Вопрос 3: Порт SSH
    echo ""
    echo -e "${BOLD}[3/5]${NC}"
    SSH_PORT=$(ask_number "Укажите порт SSH" "22" "1" "65535")

    # Вопрос 4: Firewall
    echo ""
    echo -e "${BOLD}[4/5]${NC}"
    if ask_yes_no "Включить firewall (UFW)?" "y"; then
        ENABLE_FIREWALL="true"
    fi

    # Вопрос 5: Подтверждение
    echo ""
    echo -e "${BOLD}[5/5]${NC}"
    echo -e "${CYAN}Проверка параметров:${NC}"
    echo "  • Обновление: $RUN_UPGRADE"
    echo "  • Пользователь: $CREATE_NEW_USER"
    [[ "$CREATE_NEW_USER" == "true" ]] && echo "    - Имя: $NEW_USERNAME"
    echo "  • Порт SSH: $SSH_PORT"
    echo "  • Firewall: $ENABLE_FIREWALL"
    echo ""

    if ask_yes_no "Применить настройки?" "n"; then
        return 0
    else
        log_warning "Настройка отменена"
        return 1
    fi
}

# =============================================================================
# Основные функции
# =============================================================================

run_system_update() {
    log_header "Обновление системы"
    update_packages
    [[ "$RUN_UPGRADE" == "true" ]] && upgrade_packages
    log_success "Обновление завершено"
}

run_user_setup() {
    [[ "$CREATE_NEW_USER" != "true" ]] && return 0

    log_header "Настройка пользователя"

    ensure_sudo

    # Сначала создаем пользователя
    setup_user "$NEW_USERNAME" "" "true" "$USER_PASSWORD"

    # Затем генерируем ключи если нужно
    if [[ "$SSH_KEY_MODE" == "generate" ]]; then
        setup_ssh_dir "$NEW_USERNAME"
        GENERATED_KEY_FILE=$(generate_ssh_keys "$NEW_USERNAME" "$SSH_KEY_TYPE" 2>/dev/null | tail -1)
        SSH_KEY=$(get_public_key "$GENERATED_KEY_FILE")

        # Добавляем сгенерированный ключ в authorized_keys
        add_ssh_key "$NEW_USERNAME" "$SSH_KEY"

        echo ""
        echo -e "${YELLOW}⚠️  Сохраните приватный ключ! ⚠️${NC}"
        echo ""
        get_private_key "$GENERATED_KEY_FILE"
        echo ""
        echo -e "${YELLOW}Команда для подключения:${NC}"
        echo "  ssh -i ~/.ssh/vps_${NEW_USERNAME} -p $SSH_PORT ${NEW_USERNAME}@<server-ip>"
        echo ""
    elif [[ "$SSH_KEY_MODE" == "paste" && -n "$SSH_KEY" ]]; then
        # Добавляем вставленный ключ
        add_ssh_key "$NEW_USERNAME" "$SSH_KEY"
    fi

    log_success "Пользователь $NEW_USERNAME настроен"
}

run_root_ssh_key() {
    # Если не создаем нового пользователя, но ключ указан - ставим для root
    if [[ "$CREATE_NEW_USER" != "true" && -n "$SSH_KEY" ]]; then
        log_header "Настройка SSH ключа для root"

        if [[ "$SSH_KEY_MODE" == "generate" ]]; then
            setup_ssh_dir "root"
            GENERATED_KEY_FILE=$(generate_ssh_keys "root" "$SSH_KEY_TYPE")
            SSH_KEY=$(get_public_key "$GENERATED_KEY_FILE")

            echo ""
            echo -e "${YELLOW}⚠️  Сохраните приватный ключ! ⚠️${NC}"
            cat "$GENERATED_KEY_FILE"
            echo ""
        fi

        setup_ssh_dir "root"
        add_ssh_key "root" "$SSH_KEY"
        log_success "SSH ключ установлен для root"
    fi
}

run_ssh_config() {
    log_header "Настройка SSH"

    local permit_root="no"
    [[ "$CREATE_NEW_USER" != "true" ]] && permit_root="prohibit-password"

    local password_auth="no"
    [[ "$CREATE_NEW_USER" == "true" && "$USER_AUTH_METHOD" == "password" ]] && password_auth="yes"

    backup_file "/etc/ssh/sshd_config"
    configure_ssh "$SSH_PORT" "$permit_root" "$password_auth" "yes"

    log_success "SSH настроен"
}

run_firewall_setup() {
    [[ "$ENABLE_FIREWALL" != "true" ]] && return 0

    setup_firewall "$SSH_PORT" "true"
    log_success "Firewall настроен"
}

run_ssh_restart() {
    log_header "Перезапуск SSH"

    echo -e "${YELLOW}⚠️  ВНИМАНИЕ ⚠️${NC}"
    echo "  1. Не закрывайте текущую сессию SSH"
    echo "  2. Откройте НОВОЕ подключение на порту $SSH_PORT"
    echo "  3. Убедитесь что подключение работает"
    echo ""

    if ask_yes_no "Продолжить?" "y"; then
        restart_ssh
        log_success "SSH перезапущен"
    else
        log_warning "Перезапустите SSH вручную: systemctl restart ssh"
    fi
}

show_final_info() {
    log_header "Завершение"

    echo -e "${GREEN}✓ Настройка VPS завершена!${NC}"
    echo ""
    echo "Параметры:"
    echo "  • Порт SSH: $SSH_PORT"
    [[ "$CREATE_NEW_USER" == "true" ]] && echo "  • Пользователь: $NEW_USERNAME"
    echo "  • Firewall: $ENABLE_FIREWALL"
    echo ""
    echo "Лог: $LOG_FILE"
    echo ""

    [[ "$ENABLE_FIREWALL" == "true" ]] && show_ufw_status
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    check_root
    init_logging
    log_to_file "===== Запуск скрипта ====="
    detect_os

    show_welcome

    if ! run_dialog; then
        exit 0
    fi

    run_system_update
    run_user_setup
    run_root_ssh_key
    run_ssh_config
    run_firewall_setup
    run_ssh_restart
    show_final_info

    log_to_file "===== Скрипт завершен ====="
    log_success "Все этапы выполнены!"
}

main "$@"
