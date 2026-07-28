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

# Идемпотентное выполнение команды: если успех — ✅, иначе — ⚠️
idempotent_cmd() {
    local desc="$1"
    shift
    if "$@"; then
        echo "✅ ${desc}"
    else
        echo "⚠️ ${desc}"
        return 1
    fi
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
N8N_DOMAIN="${N8N_DOMAIN:-}"
N8N_PROXY_PORT="${N8N_PROXY_PORT:-8443}"
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

# Безопасная загрузка внешнего конфига (построчный парсинг вместо source)
if [[ -f "${CONFIG_FILE}" ]]; then
    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        case "$key" in
            GROUP_NAME)            GROUP_NAME="$value" ;;
            GIT_EMAIL_DOMAIN)      GIT_EMAIL_DOMAIN="$value" ;;
            PROJECTS_DIR)          PROJECTS_DIR="$value" ;;
            SECRETS_DIR)           SECRETS_DIR="$value" ;;
            CONFIG_DIR)            CONFIG_DIR="$value" ;;
            SCRIPTS_DIR)           SCRIPTS_DIR="$value" ;;
            N8N_PORT)              N8N_PORT="$value" ;;
            N8N_WEBHOOK_URL)       N8N_WEBHOOK_URL="$value" ;;
            N8N_DOMAIN)            N8N_DOMAIN="$value" ;;
            N8N_PROXY_PORT)        N8N_PROXY_PORT="$value" ;;
            GOLANGCI_LINT_VERSION) GOLANGCI_LINT_VERSION="$value" ;;
            MIN_DISK_SPACE_MB)     MIN_DISK_SPACE_MB="$value" ;;
            HOME_DIR_PERMS)        HOME_DIR_PERMS="$value" ;;
            UMASK)                 UMASK="$value" ;;
            INSTALL_GO)            INSTALL_GO="$value" ;;
            INSTALL_JS)            INSTALL_JS="$value" ;;
            INSTALL_CSS)           INSTALL_CSS="$value" ;;
            INSTALL_MD)            INSTALL_MD="$value" ;;
            INSTALL_PHP)           INSTALL_PHP="$value" ;;
            *) echo "⚠️ Неизвестный ключ в конфиге: $key" >&2 ;;
        esac
    done < "${CONFIG_FILE}"
    ok "Конфигурация загружена: ${CONFIG_FILE}"
else
    skip "Конфиг не найден (${CONFIG_FILE}), используются значения по умолчанию"
fi

# ─── Прогресс-бар ───
TOTAL_STEPS=11
CURRENT_STEP=0
BAR_WIDTH=20

show_progress() {
    local desc="$1"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local pct=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((CURRENT_STEP * BAR_WIDTH / TOTAL_STEPS))
    local empty=$((BAR_WIDTH - filled))
    local bar=""
    local i
    for ((i = 0; i < filled; i++)); do bar+="█"; done
    for ((i = 0; i < empty; i++)); do bar+="░"; done
    echo ""
    printf "[%s] %3d%%  Шаг %d/%d: %s\n" "$bar" "$pct" "$CURRENT_STEP" "$TOTAL_STEPS" "$desc"
    echo ""
}

# =============================================================================
# 0.0 — Предварительные проверки
# =============================================================================

show_progress "Предварительные проверки"

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
    echo "📦 Установка curl..."
    apt-get install -y curl
    curl --fail --silent --show-error -o /tmp/node-setup.sh https://deb.nodesource.com/setup_20.x \
        && echo "⚠️ Внимание: выполняется скачанный скрипт. Убедитесь, что URL доверенный: https://deb.nodesource.com/setup_20.x" \
        && bash /tmp/node-setup.sh \
        && rm -f /tmp/node-setup.sh
    echo "📦 Установка Node.js..."
    apt-get install -y nodejs
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
    echo "📦 Установка Python 3 и pip..."
    apt-get install -y python3 python3-pip
    ok "Python 3 установлен: $(python3 --version)"
else
    fail "Python 3 обязателен. Прерывание."
    exit 1
fi

if command -v pip3 &>/dev/null; then
    ok "pip3 установлен"
else
    echo "📦 Установка pip3..."
    apt-get install -y python3-pip
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
    fail "Недостаточно места на диске: ${AVAIL_SPACE}M свободно (требуется минимум ${MIN_DISK_SPACE_MB}M)"
    exit 1
fi
ok "Свободное место на диске: ${AVAIL_SPACE}M"

# Проверка git
if command -v git &>/dev/null; then
    GIT_VERSION=$(git --version 2>/dev/null || echo "unknown")
    ok "Git установлен: ${GIT_VERSION}"
elif ask_if "full" "Git не найден. Установить?"; then
    echo "📦 Установка Git..."
    apt-get install -y git
    ok "Git установлен: $(git --version)"
else
    fail "Git обязателен. Прерывание."
    exit 1
fi

# Проверка curl
if command -v curl &>/dev/null; then
    ok "curl установлен"
elif ask_if "full" "curl не найден. Установить?"; then
    echo "📦 Установка curl..."
    apt-get install -y curl
    ok "curl установлен"
else
    fail "curl обязателен. Прерывание."
    exit 1
fi

# Проверка build-essential (gcc/g++ для node-gyp в n8n)
if command -v gcc &>/dev/null && command -v g++ &>/dev/null; then
    ok "build-essential (gcc/g++) установлен"
elif ask_if "full" "build-essential не найден. Установить?"; then
    echo "📦 Установка build-essential..."
    apt-get install -y build-essential
    ok "build-essential установлен"
else
    fail "build-essential обязателен. Прерывание."
    exit 1
fi

# =============================================================================
# 0.1 — Пользователи и группы
# =============================================================================

show_progress "Создание пользователей и группы ${GROUP_NAME}"

# Создание группы
if getent group "${GROUP_NAME}" &>/dev/null; then
    skip "Группа ${GROUP_NAME} (уже существует)"
else
    groupadd "${GROUP_NAME}"
    ok "Группа ${GROUP_NAME}"
fi

for user_entry in "${USERS[@]}"; do
    username="${user_entry%%:*}"
    description="${user_entry##*:}"

    if id "${username}" &>/dev/null; then
        skip "Пользователь ${username} уже существует"
    else
        useradd -m -G "${GROUP_NAME}" -s /bin/bash -c "${description}" "${username}"
        ok "Пользователь ${username} создан (${description})"
    fi

    # Убедиться, что пользователь в группе (на случай, если был создан ранее без неё)
    if id -nG "${username}" | grep -qw "${GROUP_NAME}"; then
        skip "  └─ ${username} уже в группе ${GROUP_NAME}"
    else
        usermod -aG "${GROUP_NAME}" "${username}"
        ok "  └─ ${username} добавлен в группу ${GROUP_NAME}"
    fi
done

# =============================================================================
# 0.2 — Права и Git-конфигурация
# =============================================================================

show_progress "Настройка прав, umask и Git-конфигурации"

for username in n8n_user openclaw antigravity_user hermes; do
    user_home="/home/${username}"

    # Создание директории проектов
    projects_dir="${PROJECTS_DIR}"
    if [[ -d "${projects_dir}" ]]; then
        skip "${PROJECTS_DIR} уже существует"
    else
        ok "Используется ${PROJECTS_DIR}"
    fi

    # umask в .bashrc
    bashrc_file="${user_home}/.bashrc"
    if grep -q "^umask ${UMASK}" "${bashrc_file}" 2>/dev/null; then
        skip "umask ${UMASK} уже настроен в ${bashrc_file}"
    else
        echo -e "\n# Установлено bootstrap-phase0.sh — общий доступ через SGID\numask ${UMASK}" >> "${bashrc_file}"
        ok "umask ${UMASK} добавлен в ${bashrc_file}"
    fi
done

# Настройка .gitconfig для каждого пользователя
declare -A GIT_CONFIGS
GIT_CONFIGS=(
    ["n8n_user"]="n8n Orchestrator:n8n@${GIT_EMAIL_DOMAIN}"
    ["openclaw"]="OpenClaw Agent:openclaw@${GIT_EMAIL_DOMAIN}"
    ["antigravity_user"]="Antigravity Critic:antigravity@${GIT_EMAIL_DOMAIN}"
    ["hermes"]="Hermes Agent:hermes@${GIT_EMAIL_DOMAIN}"
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

# SGID-бит на домашних директориях (на случай, если созданы ранее без нужных прав)
show_progress "Проверка SGID-бита на домашних директориях"
for username in n8n_user openclaw antigravity_user hermes; do
    user_home="/home/${username}"
    current_perm=$(stat -c "%a" "${user_home}" 2>/dev/null || echo "000")
    if [[ "${current_perm}" == "${HOME_DIR_PERMS}" ]]; then
        skip "SGID уже установлен на ${user_home}"
    else
        chmod "${HOME_DIR_PERMS}" "${user_home}"
        ok "SGID-бит установлен на ${user_home} (было ${current_perm})"
    fi
done

# =============================================================================
# 0.3 — Установка линтеров
# =============================================================================

show_progress "Установка линтеров в /usr/local/bin/"

# --- ruff (Python) ---
step "0.3.1" "Установка ruff (Python)"
if command -v ruff &>/dev/null; then
    RUFF_VER=$(ruff --version 2>/dev/null || echo "unknown")
    skip "ruff уже установлен: ${RUFF_VER}"
else
    pip3 install --break-system-packages ruff
    if command -v ruff &>/dev/null; then
        ok "ruff установлен: $(ruff --version)"
    else
        # Альтернативный способ — через официальный скрипт
        RUFF_INSTALL_URL="https://astral.sh/ruff/install.sh"
        curl --fail --silent --show-error -o /tmp/ruff-install.sh "${RUFF_INSTALL_URL}" \
            && echo "⚠️ Внимание: выполняется скачанный скрипт. Убедитесь, что URL доверенный: ${RUFF_INSTALL_URL}" \
            && bash /tmp/ruff-install.sh 2>&1 || true \
            && rm -f /tmp/ruff-install.sh
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
        apt-get update && apt-get install -y golang-go
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
        GOLANGCI_LINT_URL="https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh"
        curl --fail --silent --show-error -o /tmp/golangci-lint-install.sh "${GOLANGCI_LINT_URL}" \
            && echo "⚠️ Внимание: выполняется скачанный скрипт. Убедитесь, что URL доверенный: ${GOLANGCI_LINT_URL}" \
            && bash /tmp/golangci-lint-install.sh -b /usr/local/bin "${GOLANGCI_LINT_VERSION}" \
            && rm -f /tmp/golangci-lint-install.sh
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
        npm install -g eslint
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
        npm install -g stylelint stylelint-config-standard
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
        npm install -g markdownlint-cli
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
        apt-get install -y php-pear
        pear install PHP_CodeSniffer
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

show_progress "Настройка структуры секретов (${SECRETS_DIR}/)"

# Создание директории секретов
if [[ -d "${SECRETS_DIR}" ]]; then
    skip "Директория ${SECRETS_DIR}/ уже существует"
else
    mkdir -p "${SECRETS_DIR}"
    chown root:root "${SECRETS_DIR}"
    chmod 750 "${SECRETS_DIR}"
    ok "Директория ${SECRETS_DIR}/ создана (750, root:root)"
fi

# --- shared.env ---
step "0.4.1" "Создание ${SECRETS_DIR}/shared.env"
SHARED_ENV_CONTENT='# Shared secrets — подключается всеми агентами через source
# ВНИМАНИЕ: замените плейсхолдеры на реальные значения после разворачивания!

DEEPSEEK_API_KEY=sk_your_deepseek_key_here
GITHUB_TOKEN=ghp_your_github_pat_here
'

if [[ -f "${SECRETS_DIR}/shared.env" ]]; then
    skip "${SECRETS_DIR}/shared.env уже существует"
else
    echo "${SHARED_ENV_CONTENT}" > "${SECRETS_DIR}/shared.env"
    chown "root:${GROUP_NAME}" "${SECRETS_DIR}/shared.env"
    chmod 640 "${SECRETS_DIR}/shared.env"
    ok "${SECRETS_DIR}/shared.env создан (640, root:${GROUP_NAME})"
fi

# --- n8n.env ---
step "0.4.2" "Создание ${SECRETS_DIR}/n8n.env"
N8N_ENV_CONTENT="# n8n-specific secrets
# ВНИМАНИЕ: замените плейсхолдер на реальный ключ Linear API после разворачивания!

source ${SECRETS_DIR}/shared.env
LINEAR_API_KEY=lin_api_your_linear_key_here
"

if [[ -f "${SECRETS_DIR}/n8n.env" ]]; then
    skip "${SECRETS_DIR}/n8n.env уже существует"
else
    echo "${N8N_ENV_CONTENT}" > "${SECRETS_DIR}/n8n.env"
    chown n8n_user:n8n_user "${SECRETS_DIR}/n8n.env"
    chmod 600 "${SECRETS_DIR}/n8n.env"
    ok "${SECRETS_DIR}/n8n.env создан (600, n8n_user:n8n_user)"
fi

# --- openclaw.env ---
step "0.4.3" "Создание ${SECRETS_DIR}/openclaw.env"
OPENCLAW_ENV_CONTENT="# OpenClaw-specific secrets
source ${SECRETS_DIR}/shared.env
"

if [[ -f "${SECRETS_DIR}/openclaw.env" ]]; then
    skip "${SECRETS_DIR}/openclaw.env уже существует"
else
    echo "${OPENCLAW_ENV_CONTENT}" > "${SECRETS_DIR}/openclaw.env"
    chown openclaw:openclaw "${SECRETS_DIR}/openclaw.env"
    chmod 600 "${SECRETS_DIR}/openclaw.env"
    ok "${SECRETS_DIR}/openclaw.env создан (600, openclaw:openclaw)"
fi

# --- antigravity.env ---
step "0.4.4" "Создание ${SECRETS_DIR}/antigravity.env"
ANTIGRAVITY_ENV_CONTENT="# Antigravity-specific secrets
# ВНИМАНИЕ: замените плейсхолдер на реальный токен после разворачивания!

source ${SECRETS_DIR}/shared.env
ANTI_GRAVITY_TOKEN=your_antigravity_token_here
"

if [[ -f "${SECRETS_DIR}/antigravity.env" ]]; then
    skip "${SECRETS_DIR}/antigravity.env уже существует"
else
    echo "${ANTIGRAVITY_ENV_CONTENT}" > "${SECRETS_DIR}/antigravity.env"
    chown antigravity_user:antigravity_user "${SECRETS_DIR}/antigravity.env"
    chmod 600 "${SECRETS_DIR}/antigravity.env"
    ok "${SECRETS_DIR}/antigravity.env создан (600, antigravity_user:antigravity_user)"
fi

# --- hermes.env ---
step "0.4.5" "Создание ${SECRETS_DIR}/hermes.env"
HERMES_ENV_CONTENT="# Hermes-specific secrets
source ${SECRETS_DIR}/shared.env
"

if [[ -f "${SECRETS_DIR}/hermes.env" ]]; then
    skip "${SECRETS_DIR}/hermes.env уже существует"
else
    echo "${HERMES_ENV_CONTENT}" > "${SECRETS_DIR}/hermes.env"
    chown hermes:hermes "${SECRETS_DIR}/hermes.env"
    chmod 600 "${SECRETS_DIR}/hermes.env"
    ok "${SECRETS_DIR}/hermes.env создан (600, hermes:hermes)"
fi

# Добавление source в .bashrc каждого пользователя
step "0.4.6" "Настройка автозагрузки секретов в .bashrc"
for username in n8n_user openclaw antigravity_user hermes; do
    bashrc_file="/home/${username}/.bashrc"
    source_line="source ${SECRETS_DIR}/${username}.env"

    if grep -qF "${source_line}" "${bashrc_file}" 2>/dev/null; then
        skip "source секретов уже настроен в .bashrc для ${username}"
    else
        echo -e "\n# Автозагрузка секретов (bootstrap-phase0.sh)\n${source_line}" >> "${bashrc_file}"
        ok "source ${SECRETS_DIR}/${username}.env добавлен в .bashrc для ${username}"
    fi
done

# =============================================================================
# 0.5 — Конфигурация
# =============================================================================

show_progress "Настройка структуры конфигурации (${CONFIG_DIR}/)"

# Создание директории конфигурации
if [[ -d "${CONFIG_DIR}" ]]; then
    skip "Директория ${CONFIG_DIR}/ уже существует"
else
    mkdir -p "${CONFIG_DIR}"
    chown "root:${GROUP_NAME}" "${CONFIG_DIR}"
    chmod 2775 "${CONFIG_DIR}"
    ok "Директория ${CONFIG_DIR}/ создана (2775, root:${GROUP_NAME})"
fi

# Проверка SGID на существующей директории
current_config_perm=$(stat -c "%a" "${CONFIG_DIR}" 2>/dev/null || echo "000")
if [[ "${current_config_perm}" != "2775" ]]; then
    chmod 2775 "${CONFIG_DIR}"
fi

# --- repo-map.json ---
step "0.5.1" "Создание ${CONFIG_DIR}/repo-map.json"
REPO_MAP_CONTENT='{
  "repos": []
}
'

if [[ -f "${CONFIG_DIR}/repo-map.json" ]]; then
    skip "${CONFIG_DIR}/repo-map.json уже существует"
else
    echo "${REPO_MAP_CONTENT}" > "${CONFIG_DIR}/repo-map.json"
    chown "root:${GROUP_NAME}" "${CONFIG_DIR}/repo-map.json"
    chmod 664 "${CONFIG_DIR}/repo-map.json"
    ok "${CONFIG_DIR}/repo-map.json создан (664, root:${GROUP_NAME})"
fi

# --- reviewer_prompt.md ---
step "0.5.2" "Создание ${CONFIG_DIR}/reviewer_prompt.md"
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

if [[ -f "${CONFIG_DIR}/reviewer_prompt.md" ]]; then
    skip "${CONFIG_DIR}/reviewer_prompt.md уже существует"
else
    echo "${REVIEWER_PROMPT_CONTENT}" > "${CONFIG_DIR}/reviewer_prompt.md"
    chown "root:${GROUP_NAME}" "${CONFIG_DIR}/reviewer_prompt.md"
    chmod 664 "${CONFIG_DIR}/reviewer_prompt.md"
    ok "${CONFIG_DIR}/reviewer_prompt.md создан (664, root:${GROUP_NAME})"
fi

# =============================================================================
# 0.6 — Установка n8n
# =============================================================================

show_progress "Установка n8n (npm, не Docker)"
echo "  ⏱️  ВНИМАНИЕ: если n8n ещё не установлен — установка через npm может занять 10–15 минут."

# Установка n8n глобально от имени n8n_user
step "0.6.1" "Установка n8n через npm"

# Путь к npm global prefix для n8n_user
NPM_PREFIX="/home/n8n_user/.npm-global"

# Проверяем, установлен ли уже n8n (по бинарнику в npm-prefix и через command -v с правильным PATH)
if [[ -x "${NPM_PREFIX}/bin/n8n" ]] || sudo -u n8n_user bash -c "export PATH=\"${NPM_PREFIX}/bin:\$PATH\" && command -v n8n" &>/dev/null; then
    N8N_VER=$(sudo -u n8n_user bash -c "export PATH=\"${NPM_PREFIX}/bin:\$PATH\" && n8n --version" 2>/dev/null || echo "unknown")
    skip "n8n уже установлен: ${N8N_VER}"
else
    echo "  📦 Установка n8n через npm (может занять 10–15 минут)..."
    # ПРИМЕЧАНИЕ: большое количество warn'ов от npm (uuid-дубликаты и т.п.) —
    # это нормально, они исходят из глубины дерева зависимостей n8n.

    # Убедимся, что у n8n_user есть права на глобальную установку npm
    # Настраиваем npm prefix для n8n_user, чтобы избежать EACCES
    sudo -u n8n_user mkdir -p "${NPM_PREFIX}"
    sudo -u n8n_user npm config set prefix "${NPM_PREFIX}" 2>/dev/null || true

    # Добавляем в PATH через .bashrc, если ещё не добавлено
    if ! grep -qF "${NPM_PREFIX}/bin" "/home/n8n_user/.bashrc" 2>/dev/null; then
        echo -e "\n# npm global prefix (bootstrap-phase0.sh)\nexport PATH=\"${NPM_PREFIX}/bin:\$PATH\"" >> "/home/n8n_user/.bashrc"
    fi

    sudo -u n8n_user bash -c "export PATH=\"${NPM_PREFIX}/bin:\$PATH\" && npm install -g n8n"
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
EnvironmentFile=${SECRETS_DIR}/n8n.env
Environment=N8N_PORT=${N8N_PORT}
Environment=N8N_HOST=0.0.0.0
Environment=N8N_PROTOCOL=http
Environment=NODE_ENV=production
Environment=WEBHOOK_URL=${N8N_WEBHOOK_URL}
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

# ─── STEP 0.6.4: Настройка reverse proxy (Caddy) для n8n ───
CADDY_PORT="${N8N_PROXY_PORT:-8443}"

if [[ -n "${N8N_DOMAIN:-}" ]]; then
    echo ""
    echo "[STEP 0.6.4] Настройка reverse proxy (Caddy) для n8n"

    N8N_CADDY="/etc/caddy/sites/n8n.conf"

    if [[ -f "${N8N_CADDY}" ]]; then
        echo "  [SKIP] Конфиг Caddy для n8n уже существует: ${N8N_CADDY}"
    else
        mkdir -p /etc/caddy/sites

        cat > "${N8N_CADDY}" << CADDYEOF
${N8N_DOMAIN}:${CADDY_PORT} {
    reverse_proxy localhost:${N8N_PORT}
}
CADDYEOF

        echo "  [OK] Конфиг Caddy создан: ${N8N_CADDY} (порт ${CADDY_PORT})"

        # Настраиваем Caddy на нужный порт если ещё не настроен
        if ! grep -q ":${CADDY_PORT}" /etc/caddy/Caddyfile 2>/dev/null; then
            # Добавляем глобальный блок для порта
            cat > /etc/caddy/Caddyfile_caddy << 'CADDYGLOBAL'
{
    http_port 80
    https_port CADDY_PORT_PLACEHOLDER
}
import /etc/caddy/sites/*.conf
CADDYGLOBAL
            sed -i "s/CADDY_PORT_PLACEHOLDER/${CADDY_PORT}/" /etc/caddy/Caddyfile_caddy
            # Не перезаписываем если уже есть Caddyfile
            if [[ ! -f /etc/caddy/Caddyfile ]]; then
                mv /etc/caddy/Caddyfile_caddy /etc/caddy/Caddyfile
            else
                rm -f /etc/caddy/Caddyfile_caddy
            fi
        fi

        # Перезагружаем Caddy
        if systemctl is-active --quiet caddy 2>/dev/null; then
            systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null || true
            echo "  [OK] Caddy перезагружен"
        else
            echo "  ⚠️  Caddy не запущен. Запустите: systemctl start caddy"
        fi
    fi

    echo ""
    echo "  n8n будет доступен по адресу: https://${N8N_DOMAIN}:${CADDY_PORT}"
    echo "  ⚠️  Для доступа без порта (https://${N8N_DOMAIN}) — настройте fallback в 3x-ui:"
    echo "      SNI: ${N8N_DOMAIN} → Dest: localhost:${CADDY_PORT}"
else
    echo ""
    echo "[STEP 0.6.4] Настройка reverse proxy для n8n"
    echo "  [SKIP] N8N_DOMAIN не задан — reverse proxy не настраивается"
fi

# =============================================================================
# 0.7 — Sudo-правило для n8n → openclaw
# =============================================================================

show_progress "Создание sudo-правила для n8n_user → openclaw"

SUDOERS_FILE="/etc/sudoers.d/n8n-agent"
SUDOERS_CONTENT="n8n_user ALL=(openclaw) NOPASSWD: ${SCRIPTS_DIR}/agent_loop.sh"

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

show_progress "Создание директории ${SCRIPTS_DIR}/"

if [[ -d "${SCRIPTS_DIR}" ]]; then
    skip "Директория ${SCRIPTS_DIR}/ уже существует"
else
    mkdir -p "${SCRIPTS_DIR}"
    chown "root:${GROUP_NAME}" "${SCRIPTS_DIR}"
    chmod 2775 "${SCRIPTS_DIR}"
    ok "Директория ${SCRIPTS_DIR}/ создана (2775, root:${GROUP_NAME})"
fi

# Проверка SGID на существующей директории
current_scripts_perm=$(stat -c "%a" "${SCRIPTS_DIR}" 2>/dev/null || echo "000")
if [[ "${current_scripts_perm}" != "2775" ]]; then
    chmod 2775 "${SCRIPTS_DIR}"
fi

# =============================================================================
# 0.9 — Финальные проверки
# =============================================================================

show_progress "Финальные проверки"

# Временно отключаем set -e, чтобы одиночные сбои проверок не прерывали скрипт.
# Все ошибки аккумулируются в FAIL_COUNT и показываются в итоговом отчёте.
set +e

FAIL_COUNT=0

# ---------------------------------------------------------------------------
# Проверка пользователей и групп
# ---------------------------------------------------------------------------

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка пользователей и групп"
echo "──────────────────────────────────────────"

# Сколько пользователей состоит в группе
GROUP_MEMBER_COUNT=$(getent group "${GROUP_NAME}" 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -c -v '^$' || echo "0")
GROUP_MEMBER_COUNT=$(echo "${GROUP_MEMBER_COUNT}" | tr -d ' ')

if getent group "${GROUP_NAME}" &>/dev/null; then
    echo "  ✅ Группа ${GROUP_NAME}: ${GROUP_MEMBER_COUNT} пользователей"
else
    echo "  ⚠️ Группа ${GROUP_NAME}: НЕ существует"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

for username in n8n_user openclaw antigravity_user hermes; do
    if id "${username}" &>/dev/null; then
        UID_VAL=$(id -u "${username}" 2>/dev/null || echo "?")
        USER_GROUPS=$(id -nG "${username}" 2>/dev/null | tr ' ' ',' || echo "?")
        if echo "${USER_GROUPS}" | grep -q "${GROUP_NAME}"; then
            echo "  ✅ ${username}: uid=${UID_VAL}, группы: ${USER_GROUPS}"
        else
            echo "  ⚠️ ${username}: uid=${UID_VAL}, НЕ в группе ${GROUP_NAME}! Группы: ${USER_GROUPS}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo "  ⚠️ ${username}: НЕ существует"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# ---------------------------------------------------------------------------
# Проверка сервисов (n8n)
# ---------------------------------------------------------------------------

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка сервисов"
echo "──────────────────────────────────────────"

if systemctl is-active n8n &>/dev/null; then
    N8N_SVC_STATUS=$(systemctl is-active n8n 2>/dev/null || echo "unknown")
    echo "  ✅ n8n.service: ${N8N_SVC_STATUS}"
else
    N8N_SVC_STATUS=$(systemctl is-active n8n 2>/dev/null || echo "unknown")
    echo "  ⚠️ n8n.service: ${N8N_SVC_STATUS} (ожидался active)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# Даём n8n время на старт (до 15 секунд)
N8N_READY=false
for i in $(seq 1 15); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${N8N_PORT}/healthz" 2>/dev/null || echo "000")
    if [[ "${HTTP_CODE}" == "200" ]]; then
        N8N_READY=true
        break
    fi
    sleep 1
done

if ${N8N_READY}; then
    echo "  ✅ n8n healthz: http://localhost:${N8N_PORT}/healthz → 200 OK"
else
    echo "  ⚠️ n8n healthz: http://localhost:${N8N_PORT}/healthz → нет ответа"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Проверка линтеров
# ---------------------------------------------------------------------------

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка линтеров"
echo "──────────────────────────────────────────"

LINTERS=("ruff" "golangci-lint" "eslint" "stylelint" "markdownlint")
for linter in "${LINTERS[@]}"; do
    if command -v "${linter}" &>/dev/null; then
        LINTER_VERSION=$(${linter} --version 2>/dev/null | head -1 || echo "установлен")
        echo "  ✅ ${linter}: ${LINTER_VERSION}"
    else
        echo "  ⚠️ ${linter}: НЕ НАЙДЕН"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# ---------------------------------------------------------------------------
# Проверка директорий
# ---------------------------------------------------------------------------

echo ""
echo "──────────────────────────────────────────"
echo "  Проверка директорий"
echo "──────────────────────────────────────────"

for dir in "${SECRETS_DIR}" "${CONFIG_DIR}" "${SCRIPTS_DIR}"; do
    if [[ -d "${dir}" ]]; then
        DIR_PERMS=$(stat -c "%a" "${dir}" 2>/dev/null || echo "???")
        DIR_OWNER=$(stat -c "%U:%G" "${dir}" 2>/dev/null || echo "?:?")
        echo "  ✅ ${dir}/ (права: ${DIR_PERMS}, владелец: ${DIR_OWNER})"
    else
        echo "  ⚠️ ${dir}/: НЕ существует"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# Восстанавливаем строгий режим
set -euo pipefail

# =============================================================================
# Итог
# =============================================================================

echo ""
echo "══════════════════════════════════════════"
if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    echo -e "  ${CLR_GREEN}${CLR_BOLD}Установка завершена успешно!${CLR_RESET}"

    # Интерактивная настройка секретов (явный список ключей вместо парсинга файлов)
    echo ""
    echo "──────────────────────────────────────────"
    echo "  ⚙️  Настройка секретов"
    echo "──────────────────────────────────────────"
    echo ""
    echo "  Введите значения для ключей."
    echo "  Оставьте строку пустой и нажмите Enter чтобы пропустить."
    echo ""

    read -p "  Заполнить секреты сейчас? [Y/n]: " FILL_SECRETS

    if [[ "${FILL_SECRETS,,}" != "n" ]]; then
        # Авто-генерация ключа шифрования n8n
        if ! grep -q "^N8N_ENCRYPTION_KEY=" "${SECRETS_DIR}/n8n.env" 2>/dev/null; then
            N8N_KEY=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom 2>/dev/null | tr -dc 'a-f0-9' | head -c 64)
            echo "N8N_ENCRYPTION_KEY=${N8N_KEY}" >> "${SECRETS_DIR}/n8n.env"
            echo "  ✅ N8N_ENCRYPTION_KEY сгенерирован автоматически"
        fi

        # shared.env
        echo ""
        echo "  ─────────────────────────────────────"
        echo "  📄 ${SECRETS_DIR}/shared.env — общие для всех агентов"
        echo ""

        read -p "     DEEPSEEK_API_KEY (DeepSeek API): " val
        if [[ -n "$val" ]]; then
            grep -v "^DEEPSEEK_API_KEY=" "${SECRETS_DIR}/shared.env" > "${SECRETS_DIR}/shared.env.tmp" 2>/dev/null
            mv "${SECRETS_DIR}/shared.env.tmp" "${SECRETS_DIR}/shared.env" 2>/dev/null
            echo "DEEPSEEK_API_KEY=${val}" >> "${SECRETS_DIR}/shared.env"
            echo "     ✅ сохранён"
        else
            echo "     ⏭️  пропущен"
        fi

        read -p "     GITHUB_TOKEN (GitHub PAT): " val
        if [[ -n "$val" ]]; then
            grep -v "^GITHUB_TOKEN=" "${SECRETS_DIR}/shared.env" > "${SECRETS_DIR}/shared.env.tmp" 2>/dev/null
            mv "${SECRETS_DIR}/shared.env.tmp" "${SECRETS_DIR}/shared.env" 2>/dev/null
            echo "GITHUB_TOKEN=${val}" >> "${SECRETS_DIR}/shared.env"
            echo "     ✅ сохранён"
        else
            echo "     ⏭️  пропущен"
        fi

        # n8n.env
        echo ""
        echo "  ─────────────────────────────────────"
        echo "  📄 ${SECRETS_DIR}/n8n.env — оркестратор"
        echo ""

        read -p "     LINEAR_API_KEY (Linear API): " val
        if [[ -n "$val" ]]; then
            grep -v "^LINEAR_API_KEY=" "${SECRETS_DIR}/n8n.env" > "${SECRETS_DIR}/n8n.env.tmp" 2>/dev/null
            mv "${SECRETS_DIR}/n8n.env.tmp" "${SECRETS_DIR}/n8n.env" 2>/dev/null
            echo "LINEAR_API_KEY=${val}" >> "${SECRETS_DIR}/n8n.env"
            echo "     ✅ сохранён"
        else
            echo "     ⏭️  пропущен"
        fi

        echo ""
        echo "  ✅ Все секреты настроены."
    else
        echo "  ⏭️  Пропущено. Файлы для заполнения вручную:"
        echo "     ${SECRETS_DIR}/shared.env — DEEPSEEK_API_KEY, GITHUB_TOKEN"
        echo "     ${SECRETS_DIR}/n8n.env — LINEAR_API_KEY"
    fi

    # Домен для n8n
    echo ""
    echo "  ─────────────────────────────────────"
    echo "  🌐 Домен для n8n"
    echo ""
    read -p "     N8N_DOMAIN (оставьте пустым если нет домена): " val
    if [[ -n "$val" ]]; then
        if grep -q "^N8N_DOMAIN=" "${SECRETS_DIR}/n8n.env" 2>/dev/null; then
            sed -i "s|^N8N_DOMAIN=.*|N8N_DOMAIN=${val}|" "${SECRETS_DIR}/n8n.env"
        else
            echo "N8N_DOMAIN=${val}" >> "${SECRETS_DIR}/n8n.env"
        fi
        N8N_DOMAIN="${val}"
        echo "     ✅ N8N_DOMAIN=${val}"
        echo ""
        echo "     n8n будет доступен по адресу: https://${val}:8443"
        echo "     Для доступа без порта — настройте fallback в 3x-ui."
    else
        echo "     ⏭️  пропущен — n8n будет доступен только по IP:${N8N_PORT}"
    fi

    EXTERNAL_IP=$(curl -s ifconfig.me 2>/dev/null || echo "ВАШ_IP")
    if [[ -n "${N8N_DOMAIN:-}" ]]; then
        N8N_URL="https://${N8N_DOMAIN}:${N8N_PROXY_PORT:-8443}"
    else
        N8N_URL="http://${EXTERNAL_IP}:${N8N_PORT}"
    fi

    echo ""
    echo "  Следующие шаги:"
    echo "  1. Настройте repo-map.json: добавьте РАБОЧИЕ репозитории в ${CONFIG_DIR}/repo-map.json"
    echo "     (не репозитории агентов, а проекты, над которыми агенты работают)"
    echo "  2. Установите OpenClaw CLI от имени openclaw"
    echo "  3. Установите Antigravity CLI от имени antigravity_user"
    echo "  4. Установите Hermes CLI от имени hermes"
    echo "  5. Создайте ${SCRIPTS_DIR}/agent_loop.sh (основной цикл агента)"
    echo "  6. Настройте n8n workflow через веб-интерфейс: ${N8N_URL}"
    echo ""
else
    echo -e "  ${CLR_RED}${CLR_BOLD}Установка завершена с ошибками (${FAIL_COUNT}).${CLR_RESET}"
    echo ""
    echo "  Проверьте вывод выше и устраните проблемы перед продолжением."
    echo "  Скрипт идемпотентен — можно запустить повторно:"
    echo "    ssh root@VPS 'bash -s' < bootstrap-phase0.sh"
    echo ""
fi
echo "══════════════════════════════════════════"

exit ${FAIL_COUNT}
