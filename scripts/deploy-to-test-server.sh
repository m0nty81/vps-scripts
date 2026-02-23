#!/usr/bin/env bash

# Скрипт для развертывания и тестирования на тестовой VPS
# Использование: ./deploy-to-test-server.sh [debian|ubuntu|all]

set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Конфигурация тестовых серверов
# =============================================================================

declare -A SERVERS=(
    ["debian_host"]="144.31.199.219"
    ["debian_user"]="root"
    ["debian_pass"]="MAD__00__dog"
    ["ubuntu_host"]="144.31.137.38"
    ["ubuntu_user"]="root"
    ["ubuntu_pass"]="MAD__00__dog"
)

# =============================================================================
# Переменные
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
REMOTE_TMP_DIR="/tmp/vps-deploy-test"
TARGET_SERVER=""
TARGET_HOST=""
TARGET_USER=""
TARGET_PASS=""
SSH_CMD=""
SCP_CMD=""

# =============================================================================
# Функции
# =============================================================================

show_usage() {
    echo "Использование: $0 [debian|ubuntu|all]"
    echo ""
    echo "  debian   - Тестирование на Debian 12 (144.31.199.219)"
    echo "  ubuntu   - Тестирование на Ubuntu 24.04 (144.31.137.38)"
    echo "  all      - Тестирование на всех серверах"
    echo ""
}

select_server() {
    local target="$1"

    case "$target" in
        debian)
            TARGET_HOST="${SERVERS[debian_host]}"
            TARGET_USER="${SERVERS[debian_user]}"
            TARGET_PASS="${SERVERS[debian_pass]}"
            TARGET_SERVER="debian"
            ;;
        ubuntu)
            TARGET_HOST="${SERVERS[ubuntu_host]}"
            TARGET_USER="${SERVERS[ubuntu_user]}"
            TARGET_PASS="${SERVERS[ubuntu_pass]}"
            TARGET_SERVER="ubuntu"
            ;;
        all)
            # Будет обработано в главном цикле
            ;;
        *)
            echo -e "${RED}Неверный параметр: $target${NC}"
            show_usage
            exit 1
            ;;
    esac
}

# Инициализация SSH команд
init_ssh() {
    # Простое присваивание без экранирования - пароль не содержит специальных символов
    SSH_CMD="sshpass -p ${TARGET_PASS} ssh -o StrictHostKeyChecking=no -o BatchMode=no"
    SCP_CMD="sshpass -p ${TARGET_PASS} scp -o StrictHostKeyChecking=no"
}

# Проверка подключения по SSH
check_ssh_connection() {
    echo -e "${CYAN}Проверка подключения к ${TARGET_USER}@${TARGET_HOST}...${NC}"

    if ${SSH_CMD} "${TARGET_USER}@${TARGET_HOST}" "echo 'Connection OK'" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Подключение по SSH успешно${NC}"
        return 0
    else
        echo -e "${RED}✗ Не удалось подключиться${NC}"
        return 1
    fi
}

# Развертывание файлов на сервере
deploy_to_server() {
    echo -e "${CYAN}Развертывание файлов на сервере...${NC}"

    local ARCHIVE_NAME="vps-deploy-$(date +%Y%m%d_%H%M%S).tar.gz"
    local ARCHIVE_PATH="/tmp/${ARCHIVE_NAME}"

    # Создаем архив проекта
    echo -e "  Создание архива проекта..."
    tar -czf "${ARCHIVE_PATH}" \
        -C "${PROJECT_ROOT}" \
        bin lib tests config scripts docs logs reqs \
        README.md Makefile 2>/dev/null || \
    tar -czf "${ARCHIVE_PATH}" \
        -C "${PROJECT_ROOT}" \
        bin lib tests config scripts README.md Makefile

    echo -e "  Копирование архива на сервер..."
    ${SCP_CMD} "${ARCHIVE_PATH}" "${TARGET_USER}@${TARGET_HOST}:/tmp/"

    echo -e "  Распаковка архива..."
    ${SSH_CMD} "${TARGET_USER}@${TARGET_HOST}" "
        rm -rf ${REMOTE_TMP_DIR}
        mkdir -p ${REMOTE_TMP_DIR}
        tar -xzf /tmp/${ARCHIVE_NAME} -C ${REMOTE_TMP_DIR}
        rm /tmp/${ARCHIVE_NAME}
    "

    # Удаляем локальный архив
    rm -f "${ARCHIVE_PATH}"

    echo -e "${GREEN}✓ Файлы развернуты в ${REMOTE_TMP_DIR}${NC}"
}

# Запуск тестов на сервере
run_tests_on_server() {
    echo -e "${CYAN}Запуск тестов на сервере...${NC}"
    echo ""

    # Запускаем тесты структуры
    echo -e "${BOLD}=== Тесты структуры ===${NC}"
    ${SSH_CMD} -t "${TARGET_USER}@${TARGET_HOST}" "cd ${REMOTE_TMP_DIR} && bash tests/structure_test.sh" || true

    echo ""
    echo -e "${BOLD}=== Проверка синтаксиса ===${NC}"
    ${SSH_CMD} "${TARGET_USER}@${TARGET_HOST}" "cd ${REMOTE_TMP_DIR} && bash -n bin/deploy.sh && bash -n lib/*.sh && echo 'Все синтаксические проверки пройдены!'"
}

# Показать информацию о сервере
show_server_info() {
    echo ""
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}Информация о сервере (${TARGET_SERVER})${NC}"
    echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo ""

    ${SSH_CMD} "${TARGET_USER}@${TARGET_HOST}" "
        echo 'ОС:'
        grep -E '^(NAME|VERSION_ID)=' /etc/os-release 2>/dev/null || echo 'Не удалось определить'
        echo ''
        echo 'Доступная память:'
        free -h 2>/dev/null | grep Mem || echo 'Не удалось получить'
        echo ''
        echo 'Дисковое пространство:'
        df -h / 2>/dev/null | tail -1 || echo 'Не удалось получить'
        echo ''
        echo 'Пользователи с sudo:'
        grep sudo /etc/group 2>/dev/null || echo 'Не найдено'
    "

    echo ""
}

# =============================================================================
# Основная логика
# =============================================================================

main() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        echo -e "${RED}Укажите сервер для тестирования${NC}"
        show_usage
        exit 1
    fi

    if [[ "$target" == "all" ]]; then
        echo -e "${CYAN}Тестирование на всех серверах...${NC}"
        main "debian"
        echo ""
        echo -e "${CYAN}───────────────────────────────────────────────────────${NC}"
        echo ""
        main "ubuntu"
        return 0
    fi

    select_server "$target"
    init_ssh

    echo -e "${BOLD}${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         VPS Deploy - Тестирование на сервере              ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    echo -e "Сервер: ${TARGET_SERVER}"
    echo -e "Хост: ${TARGET_HOST}"
    echo -e "Пользователь: ${TARGET_USER}"
    echo ""

    # Проверяем подключение
    if ! check_ssh_connection; then
        echo -e "${RED}Не удалось подключиться к серверу${NC}"
        echo -e "${YELLOW}Убедитесь что:"
        echo -e "  1. Правильные учетные данные"
        echo -e "  2. Установлен sshpass: brew install sshpass"
        echo -e "  3. Или подключитесь вручную: ssh ${TARGET_USER}@${TARGET_HOST}"
        exit 1
    fi

    # Показываем информацию о сервере
    show_server_info

    # Развертываем файлы
    deploy_to_server

    # Запускаем тесты
    run_tests_on_server

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Тестирование на ${TARGET_SERVER} завершено${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Для ручного запуска deploy.sh:${NC}"
    echo -e "  ${SSH_CMD} -t ${TARGET_USER}@${TARGET_HOST}"
    echo -e "  cd ${REMOTE_TMP_DIR}"
    echo -e "  sudo bash bin/deploy.sh"
    echo ""
    echo -e "${CYAN}Для очистки временных файлов:${NC}"
    echo -e "  ${SSH_CMD} ${TARGET_USER}@${TARGET_HOST} 'rm -rf ${REMOTE_TMP_DIR}'"
    echo ""
}

# Запуск
main "$@"
