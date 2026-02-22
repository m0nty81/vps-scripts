#!/usr/bin/env bash

# Простой тест для проверки структуры проекта

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

passed=0
failed=0
typeset -i passed failed

test_dir_exists() {
    if [[ -d "$1" ]]; then
        echo -e "${GREEN}✓${NC} Директория существует: $1"
        ((passed++))
    else
        echo -e "${RED}✗${NC} Директория не найдена: $1"
        ((failed++))
    fi
}

test_file_exists() {
    if [[ -f "$1" ]]; then
        echo -e "${GREEN}✓${NC} Файл существует: $1"
        ((passed++))
    else
        echo -e "${RED}✗${NC} Файл не найден: $1"
        ((failed++))
    fi
}

test_file_executable() {
    if [[ -x "$1" ]]; then
        echo -e "${GREEN}✓${NC} Файл исполняем: $1"
        ((passed++))
    else
        echo -e "${RED}✗${NC} Файл не исполняем: $1"
        ((failed++))
    fi
}

echo "Запуск тестов структуры проекта..."
echo ""

# Проверка основных директорий
test_dir_exists "${PROJECT_ROOT}/bin"
test_dir_exists "${PROJECT_ROOT}/lib"
test_dir_exists "${PROJECT_ROOT}/config"
test_dir_exists "${PROJECT_ROOT}/tests"
test_dir_exists "${PROJECT_ROOT}/docs"
test_dir_exists "${PROJECT_ROOT}/scripts"
test_dir_exists "${PROJECT_ROOT}/logs"

# Проверка основных файлов
test_file_exists "${PROJECT_ROOT}/README.md"
test_file_exists "${PROJECT_ROOT}/.gitignore"
test_file_exists "${PROJECT_ROOT}/lib/common.sh"
test_file_exists "${PROJECT_ROOT}/config/config.example.sh"

# Проверка исполняемости скриптов
test_file_executable "${PROJECT_ROOT}/bin/deploy.sh"

echo ""
echo "Результаты: ${passed} пройдено, ${failed} провалено"

if [[ $failed -gt 0 ]]; then
    exit 1
fi