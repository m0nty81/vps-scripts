#!/usr/bin/env bash

# Тест структуры проекта VPS Deploy
# Проверяет наличие всех необходимых файлов и директорий

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0
warnings=0
typeset -i passed failed warnings

# =============================================================================
# Функции тестирования
# =============================================================================

test_dir_exists() {
    local dir="$1"
    local name="${2:-$dir}"
    
    if [[ -d "$dir" ]]; then
        echo -e "${GREEN}✓${NC} Директория: $name"
        ((passed++))
    else
        echo -e "${RED}✗${NC} Директория не найдена: $name"
        ((failed++))
    fi
}

test_file_exists() {
    local file="$1"
    local name="${2:-$file}"
    
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} Файл: $name"
        ((passed++))
    else
        echo -e "${RED}✗${NC} Файл не найден: $name"
        ((failed++))
    fi
}

test_file_executable() {
    local file="$1"
    local name="${2:-$file}"
    
    if [[ -x "$file" ]]; then
        echo -e "${GREEN}✓${NC} Файл исполняем: $name"
        ((passed++))
    else
        echo -e "${YELLOW}!${NC} Файл не исполняем: $name"
        ((warnings++))
    fi
}

test_file_syntax() {
    local file="$1"
    local name="${2:-$file}"
    
    if bash -n "$file" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Синтаксис OK: $name"
        ((passed++))
    else
        echo -e "${RED}✗${NC} Ошибка синтаксиса: $name"
        ((failed++))
    fi
}

# =============================================================================
# Запуск тестов
# =============================================================================

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         VPS Deploy - Тест структуры проекта               ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# -----------------------------------------------------------------------------
# Проверка основных директорий
# -----------------------------------------------------------------------------
echo -e "${YELLOW}=== Директории ===${NC}"

test_dir_exists "${PROJECT_ROOT}/bin" "bin/"
test_dir_exists "${PROJECT_ROOT}/lib" "lib/"
test_dir_exists "${PROJECT_ROOT}/config" "config/"
test_dir_exists "${PROJECT_ROOT}/tests" "tests/"
test_dir_exists "${PROJECT_ROOT}/docs" "docs/"
test_dir_exists "${PROJECT_ROOT}/scripts" "scripts/"
test_dir_exists "${PROJECT_ROOT}/logs" "logs/"
test_dir_exists "${PROJECT_ROOT}/reqs" "reqs/"

echo ""

# -----------------------------------------------------------------------------
# Проверка основных файлов проекта
# -----------------------------------------------------------------------------
echo -e "${YELLOW}=== Файлы проекта ===${NC}"

test_file_exists "${PROJECT_ROOT}/README.md" "README.md"
test_file_exists "${PROJECT_ROOT}/.gitignore" ".gitignore"
test_file_exists "${PROJECT_ROOT}/Makefile" "Makefile"

echo ""

# -----------------------------------------------------------------------------
# Проверка скриптов в bin/
# -----------------------------------------------------------------------------
echo -e "${YELLOW}=== Скрипты (bin/) ===${NC}"

test_file_exists "${PROJECT_ROOT}/bin/deploy.sh" "bin/deploy.sh"
test_file_executable "${PROJECT_ROOT}/bin/deploy.sh" "bin/deploy.sh"
test_file_syntax "${PROJECT_ROOT}/bin/deploy.sh" "bin/deploy.sh"

echo ""

# -----------------------------------------------------------------------------
# Проверка библиотек в lib/
# -----------------------------------------------------------------------------
echo -e "${YELLOW}=== Библиотеки (lib/) ===${NC}"

test_file_exists "${PROJECT_ROOT}/lib/common.sh" "lib/common.sh"
test_file_syntax "${PROJECT_ROOT}/lib/common.sh" "lib/common.sh"

test_file_exists "${PROJECT_ROOT}/lib/os_utils.sh" "lib/os_utils.sh"
test_file_syntax "${PROJECT_ROOT}/lib/os_utils.sh" "lib/os_utils.sh"

test_file_exists "${PROJECT_ROOT}/lib/ssh_utils.sh" "lib/ssh_utils.sh"
test_file_syntax "${PROJECT_ROOT}/lib/ssh_utils.sh" "lib/ssh_utils.sh"

test_file_exists "${PROJECT_ROOT}/lib/user_utils.sh" "lib/user_utils.sh"
test_file_syntax "${PROJECT_ROOT}/lib/user_utils.sh" "lib/user_utils.sh"

test_file_exists "${PROJECT_ROOT}/lib/firewall_utils.sh" "lib/firewall_utils.sh"
test_file_syntax "${PROJECT_ROOT}/lib/firewall_utils.sh" "lib/firewall_utils.sh"

test_file_exists "${PROJECT_ROOT}/lib/rollback.sh" "lib/rollback.sh"
test_file_syntax "${PROJECT_ROOT}/lib/rollback.sh" "lib/rollback.sh"

echo ""

# -----------------------------------------------------------------------------
# Проверка конфигурации
# -----------------------------------------------------------------------------
echo -e "${YELLOW}=== Конфигурация ===${NC}"

test_file_exists "${PROJECT_ROOT}/config/config.example.sh" "config/config.example.sh"

echo ""

# -----------------------------------------------------------------------------
# Проверка тестов
# -----------------------------------------------------------------------------
echo -e "${YELLOW}=== Тесты ===${NC}"

test_file_exists "${PROJECT_ROOT}/tests/structure_test.sh" "tests/structure_test.sh"
test_file_executable "${PROJECT_ROOT}/tests/structure_test.sh" "tests/structure_test.sh"

echo ""

# =============================================================================
# Результаты
# =============================================================================

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                    Результаты                             ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "  Пройдено:    ${GREEN}$passed${NC}"
echo "  Провалено:   ${RED}$failed${NC}"
echo "  Предупреждения: ${YELLOW}$warnings${NC}"
echo ""

if [[ $failed -gt 0 ]]; then
    echo -e "${RED}Тесты провалены!${NC}"
    exit 1
elif [[ $warnings -gt 0 ]]; then
    echo -e "${YELLOW}Тесты пройдены с предупреждениями${NC}"
    exit 0
else
    echo -e "${GREEN}Все тесты пройдены!${NC}"
    exit 0
fi
