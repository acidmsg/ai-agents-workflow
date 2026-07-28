#!/bin/bash
# =============================================================================
# bootstrap-phase0.sh — Phase 0: Infrastructure Bootstrap
# Мультиагентная система разработки (n8n + OpenClaw + Antigravity + Hermes)
#
# Назначение:  Идемпотентное разворачивание базовой инфраструктуры на VPS.
# Запуск:      ssh root@VPS 'bash -s' < bootstrap-phase0.sh
# Требования:  Ubuntu/Debian, Node.js 18+, Python 3, Go
#
# Версия:      1.0.0
# Дата:        2026-07-18
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Цвета для вывода
# -----------------------------------------------------------------------------
readonly CLR_GREEN='\033[0;32m'
readonly CLR_YELLOW='\033[0;33m'
readonly CLR_RED='\033[0;31m'
readonly CLR_BOLD='\033[1m'
readonly CLR_RESET='\033[0m'

# -----------------------------------------------------------------------------
# Служебные функции
# -----------------------------------------------------------------------------

# Вывод шага
step() {
    echo -e "\n${CLR_BOLD}[STEP ${1}]${CLR_RESET} ${2}"
}

# Статус: успех
ok() {
    echo -e "  ${CLR_GREEN}[OK]${CLR_RESET} ${1:-}"
}

# Статус: пропущено (уже существует)
skip() {
    echo -e "  ${CLR_YELLOW}[SKIP]${CLR_RESET} ${1:-}"
}

# Статус: ошибка
fail() {
    echo -e "  ${CLR_RED}[FAIL]${CLR_RESET} ${1:-}"
}

# -----------------------------------------------------------------------------
# Режимы работы
# -----------------------------------------------------------------------------
MODE="auto"  # auto | minimal | full

if [[ "${1:-}" == "--full" ]] || [[ "${1:-}" == "-f" ]]; then
    MODE="full"
    shift
elif [[ "${1:-}" == "--interactive" ]] || [[ "${1:-}" == "-i" ]]; then
    MODE="minimal"
    shift
fi

ask_if() {
    local min_mode="$1"
    local prompt="$2"
    local default="${3:-Y}"
    
    if [[ "${MODE}" == "auto" ]]; then
        return 0
    fi
    if [[ "${MODE}" == "minimal" ]] && [[ "${min_mode}" == "full" ]]; then
        return 0
    fi
    local yn="Y/n"
    [[ "${default}" == "N" ]] && yn="y/N"
    read -r -p "  ? ${prompt} [${yn}] " answer
    answer="${answer:-${default}}"
    [[ "${answer}" =~ ^[YyДд] ]]
}

INSTALL_GO="${INSTALL_GO:-true}"
INSTALL_JS="${INSTALL_JS:-true}"
INSTALL_CSS="${INSTALL_CSS:-true}"
INSTALL_MD="${INSTALL_MD:-true}"
INSTALL_PHP="${INSTALL_PHP:-true}"

if [[ "${MODE}" != "auto" ]]; then
    echo ""
    echo -e "${CLR_BOLD}Выбор языков и линтеров:${CLR_RESET}"
    echo "  [✓] Python + ruff           (обязательно)"
    echo ""
    INSTALL_GO=false   && ask_if "minimal" "Go + golangci-lint"         && INSTALL_GO=true
    INSTALL_JS=false   && ask_if "minimal" "JS + eslint"                && INSTALL_JS=true
    INSTALL_CSS=false  && ask_if "minimal" "CSS + stylelint"             && INSTALL_CSS=true
    INSTALL_MD=false   && ask_if "minimal" "Markdown + markdownlint"     && INSTALL_MD=true
    INSTALL_PHP=false  && ask_if "minimal" "PHP + phpcs"                && INSTALL_PHP=true
    echo ""
fi

# Проверка и вывод: команда существует → SKIP, иначе → выполняем и OK
idempotent_cmd() {
    local check_cmd="$1"
    local action_cmd="$2"
    local label="$3"

    if eval "${check_cmd}" &>/dev/null; then
        skip "${label} (уже существует)"
        return 0
    fi

    eval "${action_cmd}"
    ok "${label}"
}

# Проверка и вывод для создания файла: если файл существует → SKIP, иначе → создаём и OK
idempotent_file() {
    local filepath="$1"
    local content="$2"
    local label="$3"

    if [[ -f "${filepath}" ]]; then
        skip "${label} (файл уже существует)"
        return 0
    fi

    mkdir -p "$(dirname "${filepath}")"
    echo "${content}" > "${filepath}"
    ok "${label}"
}

# =============================================================================
# Конфигурация (значения по умолчанию)
# =============================================================================
# Если рядом лежит bootstrap-phase0.conf — значения будут переопределены.
CONFIG_FILE="$(dirname "$0")/bootstrap-phase0.conf"

# --- Значения по умолчанию ---
GROUP_NAME="${GROUP_NAME:-ai-workers}"
GIT_EMAIL_DOMAIN="${GIT_EMAIL_DOMAIN:-ai-agent.acidbox}"
PROJECTS_DIR="${PROJECTS_DIR:-/srv/projects}"
SECRETS_DIR="${SECRETS_DIR:-/opt/secrets}"
CONFIG_DIR="${CONFIG_DIR:-/opt/config}"
SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/scripts}"
N8N_PORT="${N8N_PORT:-5678}"
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-https://your-vps-domain-or-ip:5678/}"
GOLANGCI_LINT_VERSION="${GOLANGCI_LINT_VERSION:-v1.59.1}"
MIN_DISK_SPACE_MB="${MIN_DISK_SPACE_MB:-500}"
HOME_DIR_PERMS="${HOME_DIR_PERMS:-2775}"
UMASK="${UMASK:-0002}"

if [[ -z "${USERS[@]:-}" ]]; then
    USERS=(
        "n8n_user:Оркестратор n8n"
        "openclaw:Кодер OpenClaw"
        "antigravity_user:Критик Antigravity"
        "hermes:Утилита Hermes"
    )
fi

if [[ -z "${GIT_NAMES[@]:-}" ]]; then
    declare -A GIT_NAMES=(
        ["n8n_user"]="n8n Orchestrator"
        ["openclaw"]="OpenClaw Agent"
        ["antigravity_user"]="Antigravity Critic"
        ["hermes"]="Hermes Agent"
    )
fi

# Загрузка внешнего конфига (переопределяет значения выше)
if [[ -f "${CONFIG_FILE}" ]]; then
    source "${CONFIG_FILE}"
    ok "Конфигурация загружена: ${CONFIG_FILE}"
else
    skip "Конфиг не найден (${CONFIG_FILE}), используются значения по умолчанию"
fi

# Проверка и вывод: команда существует → SKIP, иначе → выполняем и OK
idempotent_cmd() {
    local check_cmd="$1"
    local action_cmd="$2"
    local label="$3"

    if eval "${check_cmd}" &>/dev/null; then
        skip "${label} (уже существует)"
        return 0
    fi

    eval "${action_cmd}"
    ok "${label}"
}

# Проверка и вывод для создания файла: если файл существует → SKIP, иначе → создаём и OK
idempotent_file() {
    local filepath="$1"
    local content="$2"
    local label="$3"

    if [[ -f "${filepath}" ]]; then
        skip "${label} (файл уже существует)"
        return 0
    fi

    # Создаём директорию, если нужно
    mkdir -p "$(dirname "${filepath}")"
    echo "${content}" > "${filepath}"
    ok "${label}"
}

# =============================================================================
# 0.0 — Предварительные проверки
# =============================================================================

step "0.0" "Предварительные проверки"

# Проверка запуска от root
if [[ "${EUID}" -ne 0 ]]; then
    fail "Скрипт должен быть запущен от root"
    echo "  Используйте: ssh root@VPS 'bash -s' < bootstrap-phase0.sh"
    exit 1
fi
ok "Скрипт запущен от root"

# Проверка nodejs / npm
if command -v node &>/dev/null; then
    NODE_VERSION=$(node --version 2>/dev/null || echo "unknown")
    ok "Node.js установлен: ${NODE_VERSION}"
elif ask_if "full" "Node.js не найден. Установить?"; then
    ok "Установка Node.js 20..."
    apt-get install -y -qq curl > /dev/null 2>&1
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null 2>&1
    apt-get install -y -qq nodejs > /dev/null 2>&1
    if command -v node &>/dev/null; then
        ok "Node.js установлен: $(node --version)"
    else
        fail "Не удалось установить Node.js"
        exit 1
    fi
else
    fail "Node.js обязателен. Прерывание."
    exit 1
fi

if command -v npm &>/dev/null; then
    NPM_VERSION=$(npm --version 2>/dev/null || echo "unknown")
    ok "npm установлен: ${NPM_VERSION}"
else
    fail "npm не найден (ставится вместе с Node.js)"
    exit 1
fi

# Проверка python3 (ставит python3-pip если нужно)
if command -v python3 &>/dev/null; then
    PY_VERSION=$(python3 --version 2>/dev/null || echo "unknown")
    ok "Python 3 установлен: ${PY_VERSION}"
elif ask_if "full" "Python 3 не найден. Установить?"; then
    apt-get install -y -qq python3 python3-pip > /dev/null 2>&1
    ok "Python 3 установлен: $(python3 --version)"
else
    fail "Python 3 обязателен. Прерывание."
    exit 1
fi

if command -v pip3 &>/dev/null; then
    ok "pip3 установлен"
else
    apt-get install -y -qq python3-pip > /dev/null 2>&1
    ok "pip3 установлен"
fi

# Проверка golang (будет установлен при выборе Go)
if command -v go &>/dev/null; then
    GO_VERSION=$(go version 2>/dev/null || echo "unknown")
    ok "Go установлен: ${GO_VERSION}"
else
    skip "Go не найден — будет установлен если выбрана поддержка Go"
fi

# Проверка дискового пространства
AVAIL_SPACE=$(df -BM / | awk 'NR==2 {print $4}' | sed 's/M//')
if [[ "${AVAIL_SPACE}" -lt "${MIN_DISK_SPACE_MB}" ]]; then
    fail "Недостаточно места на диске: ${AVAIL_SPACE}M свободно (требуется минимум "${MIN_DISK_SPACE_MB}"M)"
    exit 1
fi
ok "Свободное место на диске: ${AVAIL_SPACE}M"

# Проверка git
if command -v git &>/dev/null; then
    GIT_VERSION=$(git --version 2>/dev/null || echo "unknown")
    ok "Git установлен: ${GIT_VERSION}"
elif ask_if "full" "Git не найден. Установить?"; then
    apt-get install -y -qq git > /dev/null 2>&1
    ok "Git установлен: $(git --version)"
else
    fail "Git обязателен. Прерывание."
    exit 1
fi

# Проверка curl
if command -v curl &>/dev/null; then
    ok "curl установлен"
elif ask_if "full" "curl не найден. Установить?"; then
    apt-get install -y -qq curl > /dev/null 2>&1
    ok "curl установлен"
else
    fail "curl обязателен. Прерывание."
    exit 1
fi

# Проверка build-essential (gcc/g++ для node-gyp в n8n)
if command -v gcc &>/dev/null && command -v g++ &>/dev/null; then
    ok "build-essential (gcc/g++) установлен"
elif ask_if "full" "build-essential не найден. Установить?"; then
    apt-get install -y -qq build-essential > /dev/null 2>&1
    ok "build-essential установлен"
else
    fail "build-essential обязателен. Прерывание."
    exit 1
fi

# =============================================================================
# 0.1 — Пользователи и группы
# =============================================================================

step "0.1" "Создание пользователей и группы ai-workers"

# Создание группы ai-workers
idempotent_cmd \
    "getent group ""${GROUP_NAME}""" \
    "groupadd ""${GROUP_NAME}""" \
    "Группа ai-workers"



for user_entry in "${USERS[@]}"; do
    username="${user_entry%%:*}"
    description="${user_entry##*:}"

    if id "${username}" &>/dev/null; then
        skip "Пользователь ${username} уже существует"
    else
        useradd -m -G ""${GROUP_NAME}"" -s /bin/bash -c "${description}" "${username}"
        ok "Пользователь ${username} создан (${description})"
    fi

    # Убедиться, что пользователь в группе ai-workers (на случай, если был создан ранее без неё)
    if id -nG "${username}" | grep -qw ""${GROUP_NAME}""; then
        skip "  └─ ${username} уже в группе ai-workers"
    else
        usermod -aG ai-workers "${username}"
        ok "  └─ ${username} добавлен в группу ai-workers"
    fi
done

# =============================================================================
# 0.2 — Права и Git-конфигурация
# =============================================================================

step "0.2" "Настройка прав, umask и Git-конфигурации"

for username in n8n_user openclaw antigravity_user hermes; do
    user_home="/home/${username}"

    # Создание директории проектов
    projects_dir="${PROJECTS_DIR:-/srv/projects}"
    if [[ -d "${projects_dir}" ]]; then
        skip "/srv/projects уже существует"
    else
        # /srv/projects managed separately
        # permissions set at /srv/projects level
        # SGID set at /srv/projects level
        ok "Используется /srv/projects"
    fi

    # umask 0002 в .bashrc
    bashrc_file="${user_home}/.bashrc"
    if grep -q "^umask 0002" "${bashrc_file}" 2>/dev/null; then
        skip "umask 0002 уже настроен в ${bashrc_file}"
    else
        echo -e "\n# Установлено bootstrap-phase0.sh — общий доступ через SGID\numask 0002" >> "${bashrc_file}"
        ok "umask 0002 добавлен в ${bashrc_file}"
    fi
done

# Настройка .gitconfig для каждого пользователя
declare -A GIT_CONFIGS
GIT_CONFIGS=(
    ["n8n_user"]="n8n Orchestrator:n8n@"${GIT_EMAIL_DOMAIN}""
    ["openclaw"]="OpenClaw Agent:openclaw@"${GIT_EMAIL_DOMAIN}""
    ["antigravity_user"]="Antigravity Critic:antigravity@"${GIT_EMAIL_DOMAIN}""
    ["hermes"]="Hermes Agent:hermes@"${GIT_EMAIL_DOMAIN}""
)

for username in "${!GIT_CONFIGS[@]}"; do
    IFS=':' read -r display_name email <<< "${GIT_CONFIGS[$username]}"

    if sudo -u "${username}" git config --global --get user.name &>/dev/null; then
        skip "Git user.name уже настроен для ${username}"
    else
        sudo -u "${username}" git config --global user.name "${display_name}"
        ok "Git user.name = '${display_name}' для ${username}"
    fi

    if sudo -u "${username}" git config --global --get user.email &>/dev/null; then
        skip "Git user.email уже настроен для ${username}"
    else
        sudo -u "${username}" git config --global user.email "${email}"
        ok "Git user.email = '${email}' для ${username}"
    fi

    if sudo -u "${username}" git config --global --get init.defaultBranch &>/dev/null; then
        skip "Git defaultBranch уже настроен для ${username}"
    else
        sudo -u "${username}" git config --global init.defaultBranch main
        ok "Git defaultBranch = 'main' для ${username}"
    fi
done

# SGID-бит на домашних директориях (на случай, если созданы ранее без 2775)
step "0.2b" "Проверка SGID-бита на домашних директориях"
for username in n8n_user openclaw antigravity_user hermes; do
    user_home="/home/${username}"
    current_perm=$(stat -c "%a" "${user_home}" 2>/dev/null || echo "000")
    if [[ "${current_perm}" == "2775" ]]; then
        skip "SGID уже установлен на ${user_home}"
    else
        chmod 2775 "${user_home}"
        ok "SGID-бит установлен на ${user_home} (было ${current_perm})"
    fi
done

# =============================================================================
# 0.3 — Установка линтеров
# =============================================================================

step "0.3" "Установка линтеров в /usr/local/bin/"

# --- ruff (Python) ---
step "0.3.1" "Установка ruff (Python)"
if command -v ruff &>/dev/null; then
    RUFF_VER=$(ruff --version 2>/dev/null || echo "unknown")
    skip "ruff уже установлен: ${RUFF_VER}"
else
    pip3 install --break-system-packages ruff 2>&1 | tail -1
    if command -v ruff &>/dev/null; then
        ok "ruff установлен: $(ruff --version)"
    else
        # Альтернативный способ — через официальный скрипт
        curl -LsSf https://astral.sh/ruff/install.sh | sh 2>&1 || true
        if [[ -f "${HOME}/.cargo/bin/ruff" ]]; then
            mv "${HOME}/.cargo/bin/ruff" /usr/local/bin/ruff
            chmod 755 /usr/local/bin/ruff
        fi
        if command -v ruff &>/dev/null; then
            ok "ruff установлен (через официальный install.sh): $(ruff --version)"
        else
            fail "Не удалось установить ruff"
        fi
    fi
fi

# --- golangci-lint (Go) ---
if [[ "${INSTALL_GO}" != "true" ]]; then
    skip "golangci-lint пропущен"
else
    # Установка Go, если нет
    if ! command -v go &>/dev/null; then
        step "0.3.2a" "Установка Go"
        apt-get update -qq && apt-get install -y -qq golang-go 2>&1 | tail -1
        if command -v go &>/dev/null; then
            ok "Go установлен: $(go version)"
        else
            fail "Не удалось установить Go"
        fi
    fi
    # golangci-lint
    step "0.3.2" "Установка golangci-lint (Go)"
    if command -v golangci-lint &>/dev/null; then
        GL_VER=$(golangci-lint --version 2>/dev/null | head -1 || echo "unknown")
        skip "golangci-lint уже установлен: ${GL_VER}"
    else
        curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b /usr/local/bin "${GOLANGCI_LINT_VERSION}" 2>&1 | tail -3
        chmod 755 /usr/local/bin/golangci-lint 2>/dev/null || true
        if command -v golangci-lint &>/dev/null; then
            ok "golangci-lint установлен: $(golangci-lint --version 2>/dev/null | head -1)"
        else
            fail "Не удалось установить golangci-lint"
        fi
    fi
fi

# --- eslint (JS/TS) ---
if [[ "${INSTALL_JS}" != "true" ]]; then
    skip "eslint пропущен"
else
    step "0.3.3" "Установка eslint (JS/TS)"
if command -v eslint &>/dev/null; then
    ESL_VER=$(eslint --version 2>/dev/null || echo "unknown")
    skip "eslint уже установлен: ${ESL_VER}"
else
    npm install -g eslint 2>&1 | tail -3
    if command -v eslint &>/dev/null; then
        ok "eslint установлен: $(eslint --version)"
    else
        fail "Не удалось установить eslint"
    fi
fi
fi

# --- stylelint (CSS) ---
if [[ "${INSTALL_CSS}" != "true" ]]; then
    skip "stylelint пропущен"
else
    step "0.3.4" "Установка stylelint (CSS)"
if command -v stylelint &>/dev/null; then
    SL_VER=$(stylelint --version 2>/dev/null || echo "unknown")
    skip "stylelint уже установлен: ${SL_VER}"
else
    npm install -g stylelint stylelint-config-standard 2>&1 | tail -3
    if command -v stylelint &>/dev/null; then
        ok "stylelint установлен: $(stylelint --version)"
    else
        fail "Не удалось установить stylelint"
    fi
fi
fi

# --- markdownlint-cli (Markdown) ---
if [[ "${INSTALL_MD}" != "true" ]]; then
    skip "markdownlint-cli пропущен"
else
    step "0.3.5" "Установка markdownlint-cli (Markdown)"
if command -v markdownlint &>/dev/null; then
    MDL_VER=$(markdownlint --version 2>/dev/null || echo "unknown")
    skip "markdownlint уже установлен: ${MDL_VER}"
else
    npm install -g markdownlint-cli 2>&1 | tail -3
    if command -v markdownlint &>/dev/null; then
        ok "markdownlint установлен: $(markdownlint --version)"
    else
        fail "Не удалось установить markdownlint-cli"
    fi
fi
fi

# --- phpcs (PHP) ---
if [[ "${INSTALL_PHP}" != "true" ]]; then
    skip "phpcs пропущен"
else
    step "0.3.6" "Установка phpcs (PHP)"
    if command -v phpcs &>/dev/null; then
        PCS_VER=$(phpcs --version 2>/dev/null || echo "unknown")
        skip "phpcs уже установлен: ${PCS_VER}"
    else
        apt-get install -y -qq php-pear 2>&1 | tail -1
        pear install PHP_CodeSniffer 2>&1 | tail -3
        if command -v phpcs &>/dev/null; then
            ok "phpcs установлен"
        else
            fail "Не удалось установить phpcs"
        fi
    fi
fi

# =============================================================================
# 0.4 — Секреты
# =============================================================================

step "0.4" "Настройка структуры секретов ("${SECRETS_DIR}"/)"

# Создание директории "${SECRETS_DIR}"/
if [[ -d ""${SECRETS_DIR}"" ]]; then
    skip "Директория "${SECRETS_DIR}"/ уже существует"
else
    mkdir -p "${SECRETS_DIR}"
    chown root:root "${SECRETS_DIR}"
    chmod 750 "${SECRETS_DIR}"
    ok "Директория "${SECRETS_DIR}"/ создана (750, root:root)"
fi

# --- shared.env ---
step "0.4.1" "Создание "${SECRETS_DIR}"/shared.env"
SHARED_ENV_CONTENT='# Shared secrets — подключается всеми агентами через source
# ВНИМАНИЕ: замените плейсхолдеры на реальные значения после разворачивания!

DEEPSEEK_API_KEY=sk_your_deepseek_key_here
GITHUB_TOKEN=ghp_your_github_pat_here
'

if [[ -f ""${SECRETS_DIR}"/shared.env" ]]; then
    skip ""${SECRETS_DIR}"/shared.env уже существует"
else
    echo "${SHARED_ENV_CONTENT}" > "${SECRETS_DIR}"/shared.env
    chown "root:"${GROUP_NAME}"" "${SECRETS_DIR}"/shared.env
    chmod 640 "${SECRETS_DIR}"/shared.env
    ok ""${SECRETS_DIR}"/shared.env создан (640, root:ai-workers)"
fi

# --- n8n.env ---
step "0.4.2" "Создание "${SECRETS_DIR}"/n8n.env"
N8N_ENV_CONTENT='# n8n-specific secrets
# ВНИМАНИЕ: замените плейсхолдер на реальный ключ Linear API после разворачивания!

source "${SECRETS_DIR}"/shared.env
LINEAR_API_KEY=lin_api_your_linear_key_here
'

if [[ -f ""${SECRETS_DIR}"/n8n.env" ]]; then
    skip ""${SECRETS_DIR}"/n8n.env уже существует"
else
    echo "${N8N_ENV_CONTENT}" > "${SECRETS_DIR}"/n8n.env
    chown n8n_user:n8n_user "${SECRETS_DIR}"/n8n.env
    chmod 600 "${SECRETS_DIR}"/n8n.env
    ok ""${SECRETS_DIR}"/n8n.env создан (600, n8n_user:n8n_user)"
fi

# --- openclaw.env ---
step "0.4.3" "Создание "${SECRETS_DIR}"/openclaw.env"
OPENCLAW_ENV_CONTENT='# OpenClaw-specific secrets
source "${SECRETS_DIR}"/shared.env
'

if [[ -f ""${SECRETS_DIR}"/openclaw.env" ]]; then
    skip ""${SECRETS_DIR}"/openclaw.env уже существует"
else
    echo "${OPENCLAW_ENV_CONTENT}" > "${SECRETS_DIR}"/openclaw.env
    chown openclaw:openclaw "${SECRETS_DIR}"/openclaw.env
    chmod 600 "${SECRETS_DIR}"/openclaw.env
    ok ""${SECRETS_DIR}"/openclaw.env создан (600, openclaw:openclaw)"
fi

# --- antigravity.env ---
step "0.4.4" "Создание "${SECRETS_DIR}"/antigravity.env"
ANTIGRAVITY_ENV_CONTENT='# Antigravity-specific secrets
# ВНИМАНИЕ: замените плейсхолдер на реальный токен после разворачивания!

source "${SECRETS_DIR}"/shared.env
ANTI_GRAVITY_TOKEN=your_antigravity_token_here
'

if [[ -f ""${SECRETS_DIR}"/antigravity.env" ]]; then
    skip ""${SECRETS_DIR}"/antigravity.env уже существует"
else
    echo "${ANTIGRAVITY_ENV_CONTENT}" > "${SECRETS_DIR}"/antigravity.env
    chown antigravity_user:antigravity_user "${SECRETS_DIR}"/antigravity.env
    chmod 600 "${SECRETS_DIR}"/antigravity.env
    ok ""${SECRETS_DIR}"/antigravity.env создан (600, antigravity_user:antigravity_user)"
fi

# --- hermes.env ---
step "0.4.5" "Создание "${SECRETS_DIR}"/hermes.env"
HERMES_ENV_CONTENT='# Hermes-specific secrets
source "${SECRETS_DIR}"/shared.env
'

if [[ -f ""${SECRETS_DIR}"/hermes.env" ]]; then
    skip ""${SECRETS_DIR}"/hermes.env уже существует"
else
    echo "${HERMES_ENV_CONTENT}" > "${SECRETS_DIR}"/hermes.env
    chown hermes:hermes "${SECRETS_DIR}"/hermes.env
    chmod 600 "${SECRETS_DIR}"/hermes.env
    ok ""${SECRETS_DIR}"/hermes.env создан (600, hermes:hermes)"
fi

# Добавление source в .bashrc каждого пользователя
step "0.4.6" "Настройка автозагрузки секретов в .bashrc"
for username in n8n_user openclaw antigravity_user hermes; do
    bashrc_file="/home/${username}/.bashrc"
    source_line="source "${SECRETS_DIR}"/${username}.env"

    if grep -qF "${source_line}" "${bashrc_file}" 2>/dev/null; then
        skip "source секретов уже настроен в .bashrc для ${username}"
    else
        echo -e "\n# Автозагрузка секретов (bootstrap-phase0.sh)\n${source_line}" >> "${bashrc_file}"
        ok "source "${SECRETS_DIR}"/${username}.env добавлен в .bashrc для ${username}"
    fi
done

# =============================================================================
# 0.5 — Конфигурация
# =============================================================================

step "0.5" "Настройка структуры конфигурации (/opt/config/)"

# Создание директории /opt/config/
if [[ -d "/opt/config" ]]; then
    skip "Директория /opt/config/ уже существует"
else
    mkdir -p /opt/config
    chown "root:"${GROUP_NAME}"" /opt/config
    chmod 2775 /opt/config
    ok "Директория /opt/config/ создана (2775, root:ai-workers)"
fi

# Проверка SGID на существующей директории
current_config_perm=$(stat -c "%a" /opt/config 2>/dev/null || echo "000")
if [[ "${current_config_perm}" != "2775" ]]; then
    chmod 2775 /opt/config
fi

# --- repo-map.json ---
step "0.5.1" "Создание /opt/config/repo-map.json"
REPO_MAP_CONTENT='{
  "repos": []
}
'

if [[ -f "/opt/config/repo-map.json" ]]; then
    skip "/opt/config/repo-map.json уже существует"
else
    echo "${REPO_MAP_CONTENT}" > /opt/config/repo-map.json
    chown "root:"${GROUP_NAME}"" /opt/config/repo-map.json
    chmod 664 /opt/config/repo-map.json
    ok "/opt/config/repo-map.json создан (664, root:ai-workers)"
fi

# --- reviewer_prompt.md ---
step "0.5.2" "Создание /opt/config/reviewer_prompt.md"
REVIEWER_PROMPT_CONTENT='You are a Senior Staff Security and QA Engineer. Your task is to mercilessly review the provided code diff and ensure it meets the business requirements without introducing bugs.

Rules:
1. DO NOT rewrite the entire codebase. Point out specific lines with critical issues.
2. Focus strictly on:
   - Memory leaks, infinite loops, and unhandled exceptions
   - Security vulnerabilities (injection, insecure tokens, XSS)
   - Edge cases and race conditions
   - Architectural alignment with the existing codebase patterns
   - Business logic correctness relative to the task description
3. If basic error handling is missing, demand it.
4. Do NOT comment on code style or formatting (handled by linters).
5. Output strictly in JSON format, no other text:
   {"status": "approve" | "reject", "feedback": "specific, actionable feedback"}
6. Use "approve" ONLY if you found zero issues. Be conservative.
'

if [[ -f "/opt/config/reviewer_prompt.md" ]]; then
    skip "/opt/config/reviewer_prompt.md уже существует"
else
    echo "${REVIEWER_PROMPT_CONTENT}" > /opt/config/reviewer_prompt.md
    chown "root:"${GROUP_NAME}"" /opt/config/reviewer_prompt.md
    chmod 664 /opt/config/reviewer_prompt.md
    ok "/opt/config/reviewer_prompt.md создан (664, root:ai-workers)"
fi

# =============================================================================
# 0.6 — Установка n8n
# =============================================================================

step "0.6" "Установка n8n (npm, не Docker)"

# Установка n8n глобально от имени n8n_user
step "0.6.1" "Установка n8n через npm"
# Проверяем, установлен ли уже n8n
if sudo -u n8n_user bash -c 'command -v n8n' &>/dev/null; then
    N8N_VER=$(sudo -u n8n_user n8n --version 2>/dev/null || echo "unknown")
    skip "n8n уже установлен: ${N8N_VER}"
else
    # Убедимся, что у n8n_user есть права на глобальную установку npm
    # Настраиваем npm prefix для n8n_user, чтобы избежать EACCES
    NPM_PREFIX="/home/n8n_user/.npm-global"
    sudo -u n8n_user mkdir -p "${NPM_PREFIX}"
    sudo -u n8n_user npm config set prefix "${NPM_PREFIX}" 2>/dev/null || true

    # Добавляем в PATH через .bashrc, если ещё не добавлено
    if ! grep -qF "${NPM_PREFIX}/bin" "/home/n8n_user/.bashrc" 2>/dev/null; then
        echo -e "\n# npm global prefix (bootstrap-phase0.sh)\nexport PATH=\"${NPM_PREFIX}/bin:\$PATH\"" >> "/home/n8n_user/.bashrc"
    fi

    sudo -u n8n_user bash -c "export PATH=\"${NPM_PREFIX}/bin:\$PATH\" && npm install -g n8n" 2>&1 | tail -5
    ok "n8n установлен"
fi

# Определяем путь к бинарнику n8n для systemd
# Приоритет: глобальный npm n8n_user → /usr/bin/n8n (симлинк) → /usr/local/bin/n8n
N8N_BIN=""
for candidate in "/home/n8n_user/.npm-global/bin/n8n" "/usr/bin/n8n" "/usr/local/bin/n8n"; do
    if [[ -x "${candidate}" ]]; then
        N8N_BIN="${candidate}"
        break
    fi
done

# Если n8n не найден по ожидаемым путям — ищем через which
if [[ -z "${N8N_BIN}" ]]; then
    N8N_BIN=$(sudo -u n8n_user bash -c 'command -v n8n' 2>/dev/null || echo "/usr/bin/n8n")
fi

# Создание systemd-сервиса
step "0.6.2" "Создание systemd-сервиса n8n"

N8N_SERVICE_CONTENT="[Unit]
Description=n8n workflow automation
After=network.target

[Service]
Type=simple
User=n8n_user
Group=n8n_user
EnvironmentFile="${SECRETS_DIR}"/n8n.env
Environment=N8N_PORT="${N8N_PORT}"
Environment=N8N_HOST=0.0.0.0
Environment=N8N_PROTOCOL=http
Environment=NODE_ENV=production
Environment=WEBHOOK_URL="${N8N_WEBHOOK_URL}"
ExecStart=${N8N_BIN} start
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target"

SERVICE_FILE="/etc/systemd/system/n8n.service"
if [[ -f "${SERVICE_FILE}" ]]; then
    skip "Сервис n8n уже существует в ${SERVICE_FILE}"
else
    echo "${N8N_SERVICE_CONTENT}" > "${SERVICE_FILE}"
    chmod 644 "${SERVICE_FILE}"
    ok "Сервис n8n создан: ${SERVICE_FILE}"
fi

# Перезагрузка systemd и запуск
step "0.6.3" "Запуск systemd-сервиса n8n"
systemctl daemon-reload

if systemctl is-enabled n8n &>/dev/null; then
    skip "n8n уже включён в автозагрузку"
else
    systemctl enable n8n
    ok "n8n включён в автозагрузку"
fi

if systemctl is-active n8n &>/dev/null; then
    skip "n8n уже запущен"
else
    systemctl start n8n
    ok "n8n запущен"
fi

# =============================================================================
# 0.7 — Sudo-правило для n8n → openclaw
# =============================================================================

step "0.7" "Создание sudo-правила для n8n_user → openclaw"

SUDOERS_FILE="/etc/sudoers.d/n8n-agent"
SUDOERS_CONTENT="n8n_user ALL=(openclaw) NOPASSWD: "${SCRIPTS_DIR}"/agent_loop.sh"

if [[ -f "${SUDOERS_FILE}" ]]; then
    skip "Sudo-правило уже существует: ${SUDOERS_FILE}"
else
    echo "${SUDOERS_CONTENT}" > "${SUDOERS_FILE}"
    chmod 440 "${SUDOERS_FILE}"
    ok "Sudo-правило создано: ${SUDOERS_FILE} (440)"
fi

# =============================================================================
# 0.8 — Директория скриптов
# =============================================================================

step "0.8" "Создание директории "${SCRIPTS_DIR}"/"

if [[ -d ""${SCRIPTS_DIR}"" ]]; then
    skip "Директория "${SCRIPTS_DIR}"/ уже существует"
else
    mkdir -p ""${SCRIPTS_DIR}""
    chown "root:"${GROUP_NAME}"" /opt/scripts
    chmod 2775 ""${SCRIPTS_DIR}""
    ok "Директория "${SCRIPTS_DIR}"/ создана (2775, root:ai-workers)"
fi

# Проверка SGID на существующей директории
current_scripts_perm=$(stat -c "%a" /opt/scripts 2>/dev/null || echo "000")
if [[ "${current_scripts_perm}" != "2775" ]]; then
    chmod 2775 ""${SCRIPTS_DIR}""
fi

# =============================================================================
# 0.9 — Финальные проверки
# =============================================================================

step "0.9" "Финальные проверки"

FAIL_COUNT=0

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка пользователей и групп"
echo "──────────────────────────────────────────"

for username in n8n_user openclaw antigravity_user hermes; do
    if id "${username}" &>/dev/null; then
        GROUPS=$(id -nG "${username}" 2>/dev/null | tr ' ' ',')
        if echo "${GROUPS}" | grep -q "ai-workers"; then
            ok "Пользователь ${username}: группы = ${GROUPS}"
        else
            fail "Пользователь ${username}: НЕ в группе ai-workers! Группы = ${GROUPS}"
            ((FAIL_COUNT++)) || true
        fi
    else
        fail "Пользователь ${username} НЕ существует"
        ((FAIL_COUNT++)) || true
    fi
done

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка линтеров"
echo "──────────────────────────────────────────"

LINTERS=("ruff" "golangci-lint" "eslint" "stylelint" "markdownlint")
for linter in "${LINTERS[@]}"; do
    if command -v "${linter}" &>/dev/null; then
        VERSION=$(${linter} --version 2>/dev/null | head -1 || echo "установлен")
        ok "${linter}: ${VERSION}"
    else
        fail "${linter}: НЕ НАЙДЕН"
        ((FAIL_COUNT++)) || true
    fi
done

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка n8n"
echo "──────────────────────────────────────────"

# Даём n8n время на старт (до 15 секунд)
N8N_READY=false
for i in $(seq 1 15); do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:5678/healthz 2>/dev/null | grep -q "200"; then
        N8N_READY=true
        break
    fi
    sleep 1
done

if ${N8N_READY}; then
    ok "n8n отвечает: http://localhost:5678/healthz → 200 OK"
else
    fail "n8n НЕ отвечает на healthz. Проверьте: systemctl status n8n"
    ((FAIL_COUNT++)) || true
fi

if systemctl is-active n8n &>/dev/null; then
    ok "systemd-сервис n8n активен"
else
    fail "systemd-сервис n8n НЕ активен"
    ((FAIL_COUNT++)) || true
fi

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка прав на "${SECRETS_DIR}"/"
echo "──────────────────────────────────────────"

if [[ -d ""${SECRETS_DIR}"" ]]; then
    ls -la "${SECRETS_DIR}"/ 2>/dev/null || true
    ok "Директория "${SECRETS_DIR}"/ существует"
else
    fail "Директория "${SECRETS_DIR}"/ НЕ существует"
    ((FAIL_COUNT++)) || true
fi

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка прав на /opt/config/"
echo "──────────────────────────────────────────"

if [[ -d "/opt/config" ]]; then
    ls -la /opt/config/ 2>/dev/null || true
    ok "Директория /opt/config/ существует"
else
    fail "Директория /opt/config/ НЕ существует"
    ((FAIL_COUNT++)) || true
fi

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка прав на "${SCRIPTS_DIR}"/"
echo "──────────────────────────────────────────"

if [[ -d ""${SCRIPTS_DIR}"" ]]; then
    ls -la "${SCRIPTS_DIR}"/ 2>/dev/null || true
    ok "Директория "${SCRIPTS_DIR}"/ существует"
else
    fail "Директория "${SCRIPTS_DIR}"/ НЕ существует"
    ((FAIL_COUNT++)) || true
fi

# =============================================================================
# Итог
# =============================================================================

echo ""
echo "══════════════════════════════════════════════════════════"
if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    echo -e "  ${CLR_GREEN}${CLR_BOLD}Phase 0 завершена успешно.${CLR_RESET}"
    echo ""
    echo "  Следующие шаги:"
    echo "  1. Замените плейсхолдеры в "${SECRETS_DIR}"/*.env на реальные ключи"
    echo "  2. Настройте repo-map.json: добавьте репозитории в /opt/config/repo-map.json"
    echo "  3. Установите OpenClaw CLI от имени openclaw"
    echo "  4. Установите Antigravity CLI от имени antigravity_user"
    echo "  5. Установите Hermes CLI от имени hermes"
    echo "  6. Создайте "${SCRIPTS_DIR}"/agent_loop.sh"
    echo "  7. Настройте n8n workflow через веб-интерфейс (http://<VPS>:5678)"
    echo "  8. Перезапустите n8n: systemctl restart n8n"
    echo ""
else
    echo -e "  ${CLR_RED}${CLR_BOLD}Phase 0 завершена с ошибками (${FAIL_COUNT}).${CLR_RESET}"
    echo ""
    echo "  Проверьте вывод выше и устраните проблемы перед продолжением."
    echo "  Скрипт идемпотентен — можно запустить повторно:"
    echo "    ssh root@VPS 'bash -s' < bootstrap-phase0.sh"
    echo ""
fi
echo "══════════════════════════════════════════════════════════"

exit ${FAIL_COUNT}
