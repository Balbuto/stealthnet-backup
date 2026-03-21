#!/bin/bash
# ============================================
# StealthNet Backup Installer (VERSION 0.9-beta)
# ============================================
# Скачай и запусти: curl -fsSL ... | sudo bash
# Или: curl -fsSL ... | sudo bash -s < /dev/tty
# ============================================
if [[ -z "${BASH_VERSINFO[0]:-}" ]] || (( BASH_VERSINFO[0] < 4 )); then
echo -e "\033[0;31m[ОШИБКА]\033[0m Требуется Bash 4.0 или выше"
echo "Текущая версия: ${BASH_VERSION}"
exit 1
fi
set -uo pipefail
# ============================================
# Цвета для вывода
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
# ============================================
# Установка локали
# ============================================
if locale -a 2>/dev/null | grep -qi 'C.utf8\|C.UTF-8'; then
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
else
export LANG=C
export LC_ALL=C
fi
# ============================================
# Переменные по умолчанию
# ============================================
INSTALL_DIR="/opt/stealthnet-backup"
PANEL_DIR="/opt/remnawave-STEALTHNET-Bot"
BACKUP_DIR=""
DB_CONTAINER=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
TELEGRAM_ENABLED=false
EMAIL_ENABLED=false
GMAIL_USER=""
GMAIL_APP_PASSWORD=""
EMAIL_RECIPIENTS=""
RETENTION_DAILY="7"
RETENTION_WEEKLY="4"
RETENTION_MONTHLY="12"
SCHEDULE_DAILY="0 2 * * *"
SCHEDULE_WEEKLY="0 3 * * 0"
SCHEDULE_MONTHLY="0 4 1 * *"
INSTALL_SCHEDULE=true
USE_PANEL_ENV=false
NOTIFICATION_TIMEOUT=60
COMPRESSION_LEVEL=6
# ============================================
# Глобальная переменная для кода выхода
# ============================================
EXIT_CODE=0
INSTALL_LOG="/var/log/stealthnet-install.log"
# ============================================
# Логирование установки
# ============================================
exec > >(tee -a "$INSTALL_LOG") 2>&1
# ============================================
# Утилиты
# ============================================
error() {
echo -e "${RED}[ОШИБКА]${NC} $1" >&2
}
info() {
echo -e "${GREEN}[ИНФО]${NC} $1"
}
warn() {
echo -e "${YELLOW}[ВНИМАНИЕ]${NC} $1"
}
# ============================================
# Безопасный ввод с валидацией имени переменной
# ============================================
input() {
local prompt="$1"
local default="$2"
local var_name="$3"
if [[ ! "$var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
error "Недопустимое имя переменной: $var_name"
EXIT_CODE=1
return 1
fi
echo -ne "${BLUE}[ВВОД]${NC} ${prompt}"
if [[ -n "$default" ]]; then
echo -ne " [${default}]: "
else
echo -ne ": "
fi
if [[ -t 0 ]]; then
read -r value
else
read -r value < /dev/tty
fi
if [[ -z "$value" && -n "$default" ]]; then
value="$default"
fi
printf -v "$var_name" "%s" "$value"
}
# ============================================
# Подтверждение с поддержкой русского языка
# ============================================
confirm() {
local prompt="$1"
local default="${2:-y}"
local yn="д/н"
[[ "$default" == "y" ]] && yn="Д/н"
[[ "$default" == "n" ]] && yn="д/Н"
while true; do
echo -ne "${BLUE}[ПОДТВЕРЖДЕНИЕ]${NC} ${prompt} [${yn}]: "
if [[ -t 0 ]]; then
read -r answer
else
read -r answer < /dev/tty
fi
if [[ -z "$answer" ]]; then
answer="$default"
fi
case "$answer" in
[ДдYy]* ) return 0 ;;
[НнNn]* ) return 1 ;;
* ) echo "Пожалуйста, ответьте да или нет." ;;
esac
done
}
# ============================================
# Проверка прав на запись в директорию
# ============================================
check_writable() {
local dir="$1"
local parent_dir
parent_dir=$(dirname "$dir")
if [[ ! -d "$parent_dir" ]]; then
error "Родительская директория не существует: $parent_dir"
return 1
fi
if [[ ! -w "$parent_dir" ]]; then
error "Нет прав на запись в: $parent_dir"
return 1
fi
return 0
}
# ============================================
# Валидация имени контейнера Docker
# ============================================
validate_container_name() {
local name="$1"
[[ "$name" =~ ^[a-zA-Z0-9_.-]+$ ]] || return 1
return 0
}
# ============================================
# Валидация числовых значений
# ============================================
validate_number() {
local value="$1"
local default="$2"
local var_name="$3"
if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -eq 0 ]]; then
warn "Некорректное значение, используется по умолчанию: $default"
printf -v "$var_name" "%s" "$default"
else
printf -v "$var_name" "%s" "$value"
fi
}
# ============================================
# Валидация уровня сжатия
# ============================================
validate_compression_level() {
local value="$1"
if [[ ! "$value" =~ ^[1-9]$ ]]; then
warn "COMPRESSION_LEVEL вне диапазона 1-9, используется 6"
echo "6"
else
echo "$value"
fi
}
# ============================================
# Валидация таймаута уведомлений
# ============================================
validate_notification_timeout() {
local value="$1"
if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 10 ]] || [[ "$value" -gt 300 ]]; then
warn "NOTIFICATION_TIMEOUT вне диапазона 10-300, используется 60"
echo "60"
else
echo "$value"
fi
}
# ============================================
# Валидация cron-расписания
# ============================================
validate_cron_schedule() {
local schedule="$1"
local field_name="$2"
if ! [[ "$schedule" =~ ^[0-9\*\ /,-]+$ ]]; then
error "$field_name содержит недопустимые символы"
return 1
fi
local field_count
field_count=$(echo "$schedule" | tr -s ' ' | awk '{print NF}')
if [[ "$field_count" -ne 5 ]]; then
error "$field_name должно содержать 5 полей (минуты часы дни месяцы дни_недели)"
return 1
fi
read -r min hour day month weekday <<< "$schedule"
if [[ "$min" != "*" ]] && ! [[ "$min" =~ ^([0-9]|[1-5][0-9])(,([0-9]|[1-5][0-9]))*$ ]]; then
error "Минуты должны быть 0-59"
return 1
fi
if [[ "$hour" != "*" ]] && ! [[ "$hour" =~ ^([0-9]|1[0-9]|2[0-3])(,([0-9]|1[0-9]|2[0-3]))*$ ]]; then
error "Часы должны быть 0-23"
return 1
fi
if [[ "$day" != "*" ]] && ! [[ "$day" =~ ^([1-9]|[12][0-9]|3[01])(,([1-9]|[12][0-9]|3[01]))*$ ]]; then
error "Дни должны быть 1-31"
return 1
fi
if [[ "$month" != "*" ]] && ! [[ "$month" =~ ^([1-9]|1[0-2])(,([1-9]|1[0-2]))*$ ]]; then
error "Месяцы должны быть 1-12"
return 1
fi
if [[ "$weekday" != "*" ]] && ! [[ "$weekday" =~ ^([0-7])(,([0-7]))*$ ]]; then
error "Дни недели должны быть 0-7"
return 1
fi
return 0
}
# ============================================
# Проверка и установка jq/yq
# ============================================
check_and_install_tools() {
info "Проверка инструментов..."
local need_install=false
local packages=""
if ! command -v jq &>/dev/null; then
warn "jq не найден, будет установлен"
packages+="jq "
need_install=true
fi
if ! command -v yq &>/dev/null; then
warn "yq не найден, будет установлен"
if apt-cache search ^yq$ 2>/dev/null | grep -q "^yq "; then
packages+="yq "
elif apt-cache search ^yq-go$ 2>/dev/null | grep -q "^yq-go "; then
packages+="yq-go "
else
packages+="wget "
fi
need_install=true
fi
if ! command -v base64 &>/dev/null; then
packages+="coreutils "
need_install=true
fi
if ! command -v bc &>/dev/null; then
packages+="bc "
need_install=true
fi
if [[ "$need_install" == "true" ]]; then
info "Установка инструментов..."
apt-get update -qq
if ! apt-get install -y -qq $packages curl; then
error "Не удалось установить пакеты, пробуем вручную..."
if ! command -v jq &>/dev/null; then
error "jq критичен для работы скрипта"
return 1
fi
if ! command -v yq &>/dev/null && command -v wget &>/dev/null; then
info "Установка yq вручную..."
if wget -qO /usr/local/bin/yq \
https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
2>/dev/null && chmod +x /usr/local/bin/yq; then
info "yq установлен"
else
warn "Не удалось установить yq автоматически"
fi
fi
fi
fi
if ! command -v yq &>/dev/null; then
warn "yq не доступен. Автоопределение контейнера может быть неточным."
fi
if ! command -v jq &>/dev/null; then
error "jq не доступен после установки"
return 1
fi
info "Инструменты готовы: jq=$(jq --version 2>/dev/null || echo 'N/A'), yq=$(yq --version 2>/dev/null || echo 'N/A')"
return 0
}
# ============================================
# Проверка root прав
# ============================================
check_root() {
if [[ $EUID -ne 0 ]]; then
error "Этот скрипт должен быть запущен от имени root (используйте sudo)"
return 1
fi
return 0
}
# ============================================
# Проверка системы
# ============================================
check_system() {
info "Проверка системы..."
if ! command -v docker &> /dev/null; then
error "Docker не найден. Пожалуйста, установите Docker."
return 1
fi
if ! docker info &>/dev/null; then
error "Docker не запущен или недостаточно прав"
return 1
fi
if ! command -v curl &> /dev/null; then
apt-get update -qq
apt-get install -y -qq curl
fi
if ! stat --version 2>&1 | grep -q "GNU coreutils"; then
warn "stat: возможна несовместимость"
fi
if ! command -v systemctl &>/dev/null; then
warn "systemctl не найден"
fi
return 0
}
# ============================================
# Поиск контейнера БД с использованием yq
# ============================================
find_db_container() {
local panel_dir="$1"
local container_name=""
local compose_file="${panel_dir}/docker-compose.yml"
if [[ -f "$compose_file" ]] && command -v yq &>/dev/null; then
local postgres_service
postgres_service=$(yq eval 'to_entries | .[] | select(.value.image | test("postgres"; "i")) | .key' \
"$compose_file" 2>/dev/null | head -1)
if [[ -n "$postgres_service" ]]; then
container_name=$(yq eval ".services.${postgres_service}.container_name // empty" \
"$compose_file" 2>/dev/null)
if [[ -z "$container_name" ]]; then
local base_name
local project_name
base_name=$(basename "$panel_dir")
project_name=$(yq eval '.name // empty' "$compose_file" 2>/dev/null || echo "$base_name")
container_name="${project_name:-$base_name}-${postgres_service}-1"
fi
fi
fi
if [[ -z "$container_name" ]]; then
while read -r name; do
if timeout 10 docker exec "$name" pg_isready &>/dev/null; then
container_name="$name"
break
fi
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -iE "(postgres|db|database)" | grep -v "backup" || true)
fi
if [[ -z "$container_name" ]]; then
container_name=$(docker ps --filter "ancestor=postgres" --format '{{.Names}}' 2>/dev/null | head -1 || true)
fi
if [[ -n "$container_name" ]] && ! validate_container_name "$container_name"; then
warn "Некорректное имя: $container_name"
container_name=""
fi
echo "$container_name"
}
# ============================================
# Чтение переменных из .env
# ============================================
read_env_var() {
local file="$1"
local var_name="$2"
local value=""
if [[ -f "$file" ]]; then
value=$(grep -E "^${var_name}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2- | \
sed -e 's/^["\x27]//' -e 's/["\x27]$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
if command -v jq &>/dev/null && [[ -n "$value" ]]; then
value=$(jq -rn --arg v "$value" '$v' 2>/dev/null || echo "$value")
fi
fi
echo "$value"
}
# ============================================
# Безопасное экранирование
# ============================================
escape_for_source() {
local value="$1"
printf '%q' "$value"
}
escape_json() {
local value="$1"
jq -rn --arg v "$value" '$v | @json' 2>/dev/null | sed 's/^"\(.*\)"$/\1/'
}
# ============================================
# Санитизация пути
# ============================================
sanitize_path() {
local path="$1"
local real_path
if real_path=$(realpath -m "$path" 2>/dev/null); then
echo "$real_path"
else
return 1
fi
}
# ============================================
# Интерактивная конфигурация
# ============================================
configure_panel() {
info "Шаг 1: Конфигурация панели"
echo "----------------------------------------"
input "Введите директорию установки панели" "$PANEL_DIR" PANEL_DIR || return 1
if [[ ! -d "$PANEL_DIR" ]]; then
warn "Директория не найдена: $PANEL_DIR"
if ! confirm "Продолжить в любом случае?" "н"; then
return 1
fi
fi
local panel_env="${PANEL_DIR}/.env"
USE_PANEL_ENV=false
if [[ -f "$panel_env" ]]; then
info "Найден файл .env панели"
local db_name db_user db_pass bot_token detected_container
db_name=$(read_env_var "$panel_env" "POSTGRES_DB")
db_user=$(read_env_var "$panel_env" "POSTGRES_USER")
db_pass=$(read_env_var "$panel_env" "POSTGRES_PASSWORD")
bot_token=$(read_env_var "$panel_env" "BOT_TOKEN")
detected_container=$(find_db_container "$PANEL_DIR")
echo ""
echo "Обнаружено:"
[[ -n "$db_name" ]] && echo "  БД: $db_name"
[[ -n "$db_user" ]] && echo "  Пользователь: $db_user"
[[ -n "$db_pass" ]] && echo "  Пароль: [скрыт]"
[[ -n "$bot_token" ]] && echo "  Токен: [скрыт]"
[[ -n "$detected_container" ]] && echo "  Контейнер: $detected_container"
echo ""
if confirm "Использовать эти настройки?" "д"; then
USE_PANEL_ENV=true
[[ -n "$db_name" ]] && DB_NAME="$db_name"
[[ -n "$db_user" ]] && DB_USER="$db_user"
[[ -n "$db_pass" ]] && DB_PASSWORD="$db_pass"
[[ -n "$bot_token" ]] && TELEGRAM_BOT_TOKEN="$bot_token"
[[ -n "$detected_container" ]] && DB_CONTAINER="$detected_container"
fi
else
warn ".env не найден в ${PANEL_DIR}"
fi
if [[ "$USE_PANEL_ENV" != "true" ]]; then
if ! confirm "Настроить вручную?" "д"; then
return 1
fi
fi
return 0
}
configure_database() {
if [[ "$USE_PANEL_ENV" == "true" && -n "$DB_NAME" && -n "$DB_USER" && -n "$DB_PASSWORD" && -n "$DB_CONTAINER" ]]; then
info "Используются настройки БД из панели"
info "  Контейнер: $DB_CONTAINER"
info "  БД: $DB_NAME"
info "  Пользователь: $DB_USER"
return 0
fi
info "Шаг 2: Конфигурация базы данных"
echo "----------------------------------------"
if [[ -z "$DB_CONTAINER" ]]; then
local detected
detected=$(find_db_container "$PANEL_DIR")
if [[ -n "$detected" ]]; then
input "Имя контейнера PostgreSQL" "$detected" DB_CONTAINER || return 1
else
input "Имя контейнера PostgreSQL" "stealthnet-postgres" DB_CONTAINER || return 1
fi
else
input "Имя контейнера PostgreSQL" "$DB_CONTAINER" DB_CONTAINER || return 1
fi
if ! validate_container_name "$DB_CONTAINER"; then
error "Недопустимое имя: $DB_CONTAINER"
return 1
fi
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${DB_CONTAINER}$"; then
warn "Контейнер $DB_CONTAINER не запущен"
if ! confirm "Продолжить?" "н"; then
return 1
fi
fi
input "Имя базы данных" "${DB_NAME:-stealthnet}" DB_NAME || return 1
input "Пользователь БД" "${DB_USER:-postgres}" DB_USER || return 1
if [[ -z "$DB_PASSWORD" ]]; then
input "Пароль БД" "" DB_PASSWORD || return 1
while [[ -z "$DB_PASSWORD" ]]; do
error "Пароль обязателен"
input "Пароль БД" "" DB_PASSWORD || return 1
done
fi
return 0
}
configure_telegram() {
info "Шаг 3: Уведомления в Telegram"
echo "----------------------------------------"
if [[ "$USE_PANEL_ENV" == "true" && -n "$TELEGRAM_BOT_TOKEN" ]]; then
info "Токен загружен из панели"
else
input "Токен бота (от @BotFather)" "" TELEGRAM_BOT_TOKEN || return 1
fi
while [[ -z "$TELEGRAM_BOT_TOKEN" || ! "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; do
error "Неверный формат токена (пример: 123456789:AAH...)"
input "Токен бота" "" TELEGRAM_BOT_TOKEN || return 1
done
input "Chat ID (от @userinfobot)" "" TELEGRAM_CHAT_ID || return 1
while [[ -z "$TELEGRAM_CHAT_ID" ]]; do
error "Chat ID обязателен"
input "Chat ID" "" TELEGRAM_CHAT_ID || return 1
done
while [[ ! "$TELEGRAM_CHAT_ID" =~ ^-?[0-9]+$ ]]; do
error "Chat ID должен быть числом"
input "Chat ID" "" TELEGRAM_CHAT_ID || return 1
done
TELEGRAM_ENABLED=true
return 0
}
configure_email() {
info "Шаг 4: Email уведомления"
echo "----------------------------------------"
if confirm "Включить email?" "н"; then
EMAIL_ENABLED=true
input "Gmail адрес" "" GMAIL_USER || return 1
warn "Нужен App Password: https://myaccount.google.com/apppasswords"
input "App Password" "" GMAIL_APP_PASSWORD || return 1
input "Получатели (через запятую)" "$GMAIL_USER" EMAIL_RECIPIENTS || return 1
else
EMAIL_ENABLED=false
GMAIL_USER=""
GMAIL_APP_PASSWORD=""
EMAIL_RECIPIENTS=""
fi
return 0
}
configure_retention() {
info "Шаг 5: Политика хранения"
echo "----------------------------------------"
local temp_var
input "Ежедневные (дней)" "$RETENTION_DAILY" temp_var || return 1
validate_number "$temp_var" "7" RETENTION_DAILY
input "Еженедельные (недель)" "$RETENTION_WEEKLY" temp_var || return 1
validate_number "$temp_var" "4" RETENTION_WEEKLY
input "Ежемесячные (месяцев)" "$RETENTION_MONTHLY" temp_var || return 1
validate_number "$temp_var" "12" RETENTION_MONTHLY
return 0
}
configure_schedule() {
info "Шаг 6: Расписание"
echo "----------------------------------------"
if ! confirm "Включить авто-бэкапы?" "д"; then
INSTALL_SCHEDULE=false
return 0
fi
INSTALL_SCHEDULE=true
echo "Примеры: 0 2 * * * = ежедневно в 2:00"
echo "         0 3 * * 0 = воскресение в 3:00"
echo ""
input "Ежедневно" "$SCHEDULE_DAILY" SCHEDULE_DAILY || return 1
validate_cron_schedule "$SCHEDULE_DAILY" "Ежедневное расписание" || return 1
input "Еженедельно" "$SCHEDULE_WEEKLY" SCHEDULE_WEEKLY || return 1
validate_cron_schedule "$SCHEDULE_WEEKLY" "Еженедельное расписание" || return 1
input "Ежемесячно" "$SCHEDULE_MONTHLY" SCHEDULE_MONTHLY || return 1
validate_cron_schedule "$SCHEDULE_MONTHLY" "Ежемесячное расписание" || return 1
return 0
}
configure_paths() {
info "Шаг 7: Пути"
echo "----------------------------------------"
input "Директория установки" "$INSTALL_DIR" INSTALL_DIR || return 1
if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR" ]]; then
error "$INSTALL_DIR не директория"
return 1
fi
if ! check_writable "$INSTALL_DIR"; then
error "Нет прав: $INSTALL_DIR"
return 1
fi
input "Хранилище бэкапов" "${INSTALL_DIR}/backups" BACKUP_DIR || return 1
while [[ -z "$BACKUP_DIR" ]]; do
error "BACKUP_DIR не может быть пустым"
input "Хранилище бэкапов" "${INSTALL_DIR}/backups" BACKUP_DIR || return 1
done
local backup_parent
backup_parent=$(dirname "$BACKUP_DIR")
if [[ ! -d "$backup_parent" ]]; then
warn "Родительская директория не существует: $backup_parent"
if ! confirm "Создать?" "д"; then
return 1
fi
if ! mkdir -p "$backup_parent"; then
error "Не удалось создать: $backup_parent"
return 1
fi
fi
if ! check_writable "$BACKUP_DIR"; then
error "Нет прав: $BACKUP_DIR"
return 1
fi
return 0
}
# ============================================
# Установка зависимостей
# ============================================
install_dependencies() {
info "Установка зависимостей..."
apt-get update -qq
local packages="curl gzip coreutils util-linux bc"
if [[ "$EMAIL_ENABLED" == "true" ]]; then
packages="$packages mailutils msmtp-mta"
fi
if ! apt-get install -y -qq $packages; then
error "Не удалось установить"
return 1
fi
info "Зависимости установлены"
return 0
}
# ============================================
# Создание директорий с проверкой
# ============================================
create_directories() {
info "Создание директорий..."
if [[ -e "$INSTALL_DIR" && ! -d "$INSTALL_DIR" ]]; then
error "$INSTALL_DIR не директория"
return 1
fi
for dir in "$INSTALL_DIR" "$INSTALL_DIR/lib" "$INSTALL_DIR/logs" "$INSTALL_DIR/tmp" "$BACKUP_DIR"; do
if [[ -L "$dir" ]]; then
error "Директория является симлинком: $dir"
return 1
fi
mkdir -p "$dir" || return 1
chmod 750 "$dir"
done
info "Директории созданы"
return 0
}
# ============================================
# Проверка на дублирование установки
# ============================================
check_existing_installation() {
if [[ -f "${INSTALL_DIR}/config.env" ]]; then
warn "Установка существует в ${INSTALL_DIR}"
if ! confirm "Перезаписать?" "н"; then
info "Отменено"
return 2
fi
info "Перезапись..."
fi
return 0
}
# ============================================
# Генерация скриптов
# ============================================
generate_scripts() {
info "Генерация скриптов..."
if [[ ! -d "$INSTALL_DIR" ]]; then
error "Директория не существует: $INSTALL_DIR"
return 1
fi
local db_pass_escaped bot_token_escaped gmail_pass_escaped
db_pass_escaped=$(escape_for_source "$DB_PASSWORD")
bot_token_escaped=$(escape_for_source "$TELEGRAM_BOT_TOKEN")
gmail_pass_escaped=$(escape_for_source "$GMAIL_APP_PASSWORD")
local compression_level
compression_level=$(validate_compression_level "$COMPRESSION_LEVEL")
local notification_timeout
notification_timeout=$(validate_notification_timeout "$NOTIFICATION_TIMEOUT")
# ==================== CONFIG.ENV ====================
cat > "${INSTALL_DIR}/config.env" << EOF
#!/bin/bash
readonly MIN_DISK_SPACE_KB=1048576
readonly MIN_INODES_FREE=1000
readonly TELEGRAM_MAX_FILE_MB=49
readonly EMAIL_MAX_ATTACH_MB=24
readonly BACKUP_INDEX_LIMIT=100
readonly TMP_CLEANUP_AGE_MIN=60
readonly NOTIFICATION_TIMEOUT_DEFAULT=60
readonly COMPRESSION_LEVEL_MIN=1
readonly COMPRESSION_LEVEL_MAX=9
readonly MAX_FILENAME_LENGTH=200
readonly LOCK_MAX_AGE=3600
PANEL_DIR="${PANEL_DIR}"
PANEL_ENV_FILE="\${PANEL_DIR}/.env"
BASE_DIR="${INSTALL_DIR}"
BACKUP_DIR="${BACKUP_DIR}"
LOG_DIR="\${BASE_DIR}/logs"
TMP_DIR="\${BASE_DIR}/tmp"
LOCK_FILE="\${TMP_DIR}/backup.lock"
CLEANUP_LOCK_FILE="\${TMP_DIR}/cleanup.lock"
DB_CONTAINER="${DB_CONTAINER}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASSWORD='${db_pass_escaped}'
TELEGRAM_ENABLED=${TELEGRAM_ENABLED}
TELEGRAM_BOT_TOKEN='${bot_token_escaped}'
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
RETENTION_DAILY=${RETENTION_DAILY}
RETENTION_WEEKLY=${RETENTION_WEEKLY}
RETENTION_MONTHLY=${RETENTION_MONTHLY}
EMAIL_ENABLED=${EMAIL_ENABLED}
GMAIL_USER="${GMAIL_USER}"
GMAIL_APP_PASSWORD='${gmail_pass_escaped}'
EMAIL_RECIPIENTS="${EMAIL_RECIPIENTS}"
BACKUP_PREFIX="stealthnet"
MAX_BACKUP_SIZE_MB=100
COMPRESSION_LEVEL=${compression_level}
SCHEDULE_DAILY="${SCHEDULE_DAILY}"
SCHEDULE_WEEKLY="${SCHEDULE_WEEKLY}"
SCHEDULE_MONTHLY="${SCHEDULE_MONTHLY}"
NOTIFICATION_TIMEOUT=${notification_timeout}
EOF
if [[ ! -f "${INSTALL_DIR}/config.env" ]]; then
error "Не удалось создать config.env"
return 1
fi
if [[ ! -s "${INSTALL_DIR}/config.env" ]]; then
error "config.env пуст или не записан"
return 1
fi
if ! chmod 600 "${INSTALL_DIR}/config.env" 2>/dev/null; then
error "Не удалось установить права на config.env"
return 1
fi
# ==================== LIB/UTILS.SH ====================
cat > "${INSTALL_DIR}/lib/utils.sh" << 'UTILSEOF'
#!/bin/bash
set -uo pipefail
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/config.env"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
SIGNAL_HANDLED=false
log() {
local level="$1"
shift
local message="$*"
local ts
ts=$(date '+%Y-%m-%d %H:%M:%S')
case "$level" in
ERROR) echo -e "${RED}[ОШИБКА]${NC} ${ts} - ${message}" >&2 ;;
WARN)  echo -e "${YELLOW}[ВНИМАНИЕ]${NC} ${ts} - ${message}" ;;
INFO)  echo -e "${GREEN}[ИНФО]${NC} ${ts} - ${message}" ;;
DEBUG) echo -e "${BLUE}[DEBUG]${NC} ${ts} - ${message}" ;;
esac
mkdir -p "$LOG_DIR"
echo "[${level}] ${ts} - ${message}" >> "${LOG_DIR}/backup.log"
}
check_root() {
if [[ $EUID -eq 0 ]]; then
return 0
else
log "ERROR" "Требуется root"
exit 1
fi
}
validate_container_name() {
local name="$1"
[[ "$name" =~ ^[a-zA-Z0-9_.-]+$ ]] && return 0 || return 1
}
check_required_vars() {
local v
for v in DB_NAME DB_USER DB_PASSWORD DB_CONTAINER BACKUP_DIR; do
if [[ -z "${!v}" ]]; then
log "ERROR" "Переменная $v не задана"
exit 1
fi
done
if [[ "$BACKUP_DIR" == "/" ]] || [[ -z "$BACKUP_DIR" ]]; then
log "ERROR" "BACKUP_DIR не может быть корневым или пустым"
exit 1
fi
}
ensure_tmp_dir() {
if [[ ! -d "$TMP_DIR" ]]; then
mkdir -p "$TMP_DIR" || return 1
chmod 750 "$TMP_DIR" || return 1
fi
if [[ -L "$TMP_DIR" ]]; then
log "ERROR" "TMP_DIR является symlink: $TMP_DIR"
return 1
fi
local owner_uid dir_perms
owner_uid=$(stat -c '%u' "$TMP_DIR" 2>/dev/null || echo "-1")
if [[ "$owner_uid" -ne 0 ]]; then
log "ERROR" "TMP_DIR принадлежит не root: $TMP_DIR (uid=$owner_uid)"
return 1
fi
dir_perms=$(stat -c '%a' "$TMP_DIR" 2>/dev/null || echo "777")
if [[ "$dir_perms" =~ [67]$ ]]; then
log "ERROR" "TMP_DIR имеет небезопасные права: $dir_perms"
return 1
fi
if command -v mountpoint &>/dev/null && ! mountpoint -q "$TMP_DIR" 2>/dev/null; then
local fstype
fstype=$(findmnt -n -o FSTYPE "$TMP_DIR" 2>/dev/null || echo "")
if [[ "$fstype" != "tmpfs" ]]; then
log "WARN" "TMP_DIR не является tmpfs. Временные файлы могут попасть на диск."
fi
fi
return 0
}
check_pg_dump() {
if ! timeout 30 docker exec "$DB_CONTAINER" which pg_dump &>/dev/null && \
! timeout 30 docker exec "$DB_CONTAINER" command -v pg_dump &>/dev/null; then
log "ERROR" "pg_dump не найден в контейнере $DB_CONTAINER"
return 1
fi
return 0
}
check_pg_version() {
local pg_version
pg_version=$(timeout 30 docker exec "$DB_CONTAINER" psql -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
if [[ -n "$pg_version" ]]; then
if command -v bc &>/dev/null && (( $(echo "$pg_version < 9.6" | bc -l 2>/dev/null || echo 0) )); then
log "WARN" "PostgreSQL $pg_version может быть несовместима"
fi
fi
}
check_container_locale() {
local container_locale
container_locale=$(timeout 30 docker exec "$DB_CONTAINER" locale 2>/dev/null | grep -i "ctype" | head -1 || echo "")
if [[ -z "$container_locale" ]] || [[ "$container_locale" != *"UTF-8"* ]] && [[ "$container_locale" != *"utf8"* ]]; then
log "WARN" "В контейнере может не быть UTF-8 локали. Возможны проблемы с кодировкой."
fi
}
check_docker() {
if ! command -v docker &>/dev/null; then
log "ERROR" "Docker не найден"
return 1
fi
if ! validate_container_name "$DB_CONTAINER"; then
log "ERROR" "Некорректное имя: $DB_CONTAINER"
return 1
fi
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${DB_CONTAINER}$"; then
log "ERROR" "Контейнер не запущен"
return 1
fi
if ! timeout 30 docker exec "$DB_CONTAINER" pg_isready &>/dev/null && \
! timeout 30 docker exec "$DB_CONTAINER" psql --version &>/dev/null; then
log "ERROR" "PostgreSQL не готов"
return 1
fi
check_pg_version
check_container_locale
if ! check_pg_dump; then
return 1
fi
return 0
}
check_disk_space() {
local dir="${1:-$BACKUP_DIR}"
local min_kb="${2:-${MIN_DISK_SPACE_KB:-1048576}}"
local free mount_opts free_inodes
if [[ -z "$dir" ]] || [[ "$dir" == "/" ]] || [[ ! -d "$dir" ]]; then
log "ERROR" "Некорректная директория для проверки места"
return 1
fi
free=$(df -P "$dir" 2>/dev/null | awk 'NR==2{print $4}')
if [[ -z "$free" ]] || [[ "$free" -lt "$min_kb" ]]; then
log "ERROR" "Недостаточно места на диске"
return 1
fi
free_inodes=$(df -i "$dir" 2>/dev/null | awk 'NR==2{print $4}')
if [[ -n "$free_inodes" ]] && [[ "$free_inodes" -lt "${MIN_INODES_FREE:-1000}" ]]; then
log "ERROR" "Недостаточно inodes (свободно: $free_inodes)"
return 1
fi
mount_opts=$(findmnt -n -o OPTIONS "$dir" 2>/dev/null || echo "")
if [[ "$mount_opts" == *"ro"* ]]; then
log "ERROR" "Директория только для чтения"
return 1
fi
return 0
}
get_backup_path() {
local type="${1:-daily}"
local now dir filename
now=$(date '+%Y-%m-%d_%H-%M-%S')
dir="${BACKUP_DIR}/$(date '+%Y/%m/%d')"
mkdir -p "$dir"
filename="${BACKUP_PREFIX}-${type}-${now}.sql"
if [[ ${#filename} -gt ${MAX_FILENAME_LENGTH:-200} ]]; then
log "ERROR" "Имя файла слишком длинное: ${#filename} символов"
return 1
fi
echo "${dir}/${filename}"
}
get_file_size_mb() {
local file="$1"
if [[ -f "$file" ]]; then
local sz
sz=$(stat -c%s "$file" 2>/dev/null || echo 0)
[[ "$sz" =~ ^[0-9]+$ ]] && echo $((sz/1024/1024)) || echo 0
else
echo 0
fi
}
human_readable_size() {
local mb="$1"
[[ ! "$mb" =~ ^[0-9]+$ ]] && { echo "0 МБ"; return; }
(( mb > 1024 )) && echo "$((mb/1024)) ГБ" || echo "${mb} МБ"
}
acquire_lock() {
local lock_file="${1:-$LOCK_FILE}"
if [[ -z "$lock_file" ]]; then
log "ERROR" "Lock file не указан"
return 1
fi
if ! mkdir -p "$(dirname "$lock_file")" 2>/dev/null; then
log "ERROR" "Не удалось создать директорию для lock"
return 1
fi
if [[ -f "$lock_file" ]]; then
local old_pid lock_age
old_pid=$(cat "$lock_file" 2>/dev/null || echo "")
lock_age=$(($(date +%s) - $(stat -c %Y "$lock_file" 2>/dev/null || echo 0)))
if [[ -n "$old_pid" ]] && ! kill -0 "$old_pid" 2>/dev/null; then
log "WARN" "Stale lock file (PID $old_pid не существует)"
rm -f "$lock_file"
elif [[ $lock_age -gt ${LOCK_MAX_AGE:-3600} ]]; then
log "WARN" "Stale lock (>1 час), удаляем"
rm -f "$lock_file"
fi
fi
if ! exec {fd}>"$lock_file" 2>/dev/null; then
log "ERROR" "Не удалось открыть lock файл"
return 1
fi
if ! flock -n "$fd" 2>/dev/null; then
exec {fd}>&- 2>/dev/null
local old_pid
old_pid=$(cat "$lock_file" 2>/dev/null || echo "")
if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
log "WARN" "Другой процесс выполняет операцию (PID $old_pid)"
else
rm -f "$lock_file" 2>/dev/null
fi
return 1
fi
echo $$ >&"$fd"
sync
LOCK_FD=$fd
return 0
}
release_lock() {
if [[ -n "${LOCK_FD:-}" ]]; then
flock -u "$LOCK_FD" 2>/dev/null || true
exec {LOCK_FD}>&- 2>/dev/null || true
unset LOCK_FD
fi
}
safe_mktemp() {
local pattern="${1:-${TMP_DIR}/tmp_XXXXXX}"
local tmp_file
tmp_file=$(umask 077 && mktemp "$pattern" 2>/dev/null)
if [[ -z "$tmp_file" || ! -f "$tmp_file" ]]; then
log "ERROR" "Не удалось создать временный файл"
return 1
fi
echo "$tmp_file"
return 0
}
verify_backup_path() {
local file="$1"
local real_file real_dir
if [[ -z "$file" ]] || [[ -z "$BACKUP_DIR" ]] || [[ ! -d "$BACKUP_DIR" ]]; then
return 1
fi
real_file=$(realpath -e "$file" 2>/dev/null) || return 1
real_dir=$(realpath -e "$BACKUP_DIR" 2>/dev/null) || return 1
[[ "$real_file" != "${real_dir}/"* ]] && return 1
return 0
}
cleanup_normal() {
local ec=${EXIT_CODE:-$?}
if [[ "$SIGNAL_HANDLED" == "true" ]]; then
return
fi
SIGNAL_HANDLED=true
trap '' EXIT INT TERM QUIT HUP
release_lock
local td="${TMP_DIR:-${BASE_DIR:-/opt/stealthnet-backup}/tmp}"
if [[ -n "$td" && -d "$td" ]]; then
find "$td" -type f \( \
-name "*.tmp" -o \
-name "*.pgerr.*" -o \
-name "restore_*" -o \
-name "idx_*.json" -o \
-name "email_*" \
\) -mmin +${TMP_CLEANUP_AGE_MIN:-60} -delete 2>/dev/null || true
fi
exit $ec
}
cleanup_signal() {
if [[ "$SIGNAL_HANDLED" == "true" ]]; then
return
fi
SIGNAL_HANDLED=true
log "WARN" "Прерывание..."
trap '' EXIT INT TERM QUIT HUP
release_lock
exit 1
}
trap cleanup_normal EXIT
trap 'cleanup_signal' INT TERM QUIT HUP
UTILSEOF
if [[ ! -f "${INSTALL_DIR}/lib/utils.sh" ]]; then
error "Не удалось создать utils.sh"
return 1
fi
if ! chmod +x "${INSTALL_DIR}/lib/utils.sh" 2>/dev/null; then
error "Не удалось установить права на utils.sh"
return 1
fi
if [[ ! -x "${INSTALL_DIR}/lib/utils.sh" ]]; then
error "utils.sh не исполняемый"
return 1
fi
# ==================== LIB/TELEGRAM.SH ====================
cat > "${INSTALL_DIR}/lib/telegram.sh" << 'TELEGRAMEOF'
#!/bin/bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"
source "$(dirname "$0")/utils.sh"
send_telegram_message() {
local msg="$1"
[[ "$TELEGRAM_ENABLED" != "true" ]] && return 0
[[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 1
local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
set +x
local resp
resp=$(timeout 30 curl -s -X POST "$api_url" \
-d "chat_id=${TELEGRAM_CHAT_ID}" \
-d "text=${msg}" \
-d "parse_mode=HTML" \
--max-time 30 2>&1)
if echo "$resp" | grep -q '"ok":true'; then
log "INFO" "Telegram отправлено"
return 0
else
log "ERROR" "Telegram ошибка"
return 1
fi
}
send_telegram_document() {
local fp="$1"
local cap="${2:-Файл}"
[[ "$TELEGRAM_ENABLED" != "true" ]] && return 0
[[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]] && return 1
[[ ! -f "$fp" ]] && return 1
local sz
sz=$(get_file_size_mb "$fp")
if (( sz > ${TELEGRAM_MAX_FILE_MB:-49} )); then
send_telegram_message "📁 Файл слишком большой (${sz}МБ)"
return 0
fi
local api_url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument"
set +x
timeout 120 curl -s -X POST "$api_url" \
-F "chat_id=${TELEGRAM_CHAT_ID}" \
-F "document=@${fp}" \
-F "caption=${cap}" \
-F "parse_mode=HTML" \
--max-time 120 >/dev/null 2>&1
}
send_backup_notification() {
local status="$1" bf="$2" dur="$3" sz="$4" err="${5:-}"
local hn ts em st
hn=$(hostname)
ts=$(date '+%Y-%m-%d %H:%M:%S')
[[ "$status" == "success" ]] && { em="✅"; st="<b>УСПЕШНО</b>"; } || { em="❌"; st="<b>ОШИБКА</b>"; }
log "INFO" "Отправка уведомления о статусе: $status"
local msg="${em} <b>Отчет StealthNet</b>
🖥️ Сервер: <code>${hn}</code>
⏰ Время: ${ts}
📊 Статус: ${st}
📦 Файл: <code>$(basename "$bf")</code>
📏 Размер: $(human_readable_size "$sz")
⏱️ Длительность: ${dur}с"
[[ "$status" == "failed" ]] && msg="${msg}
❗ Ошибка: <pre>${err}</pre>"
send_telegram_message "$msg"
if [[ "$status" == "success" && -f "$bf" ]]; then
local fsz
fsz=$(get_file_size_mb "$bf")
(( fsz <= ${MAX_BACKUP_SIZE_MB:-100} )) && send_telegram_document "$bf" "Бэкап $(date '+%Y-%m-%d')"
fi
}
TELEGRAMEOF
if [[ ! -f "${INSTALL_DIR}/lib/telegram.sh" ]]; then
error "Не удалось создать telegram.sh"
return 1
fi
if ! chmod +x "${INSTALL_DIR}/lib/telegram.sh" 2>/dev/null; then
error "Не удалось установить права на telegram.sh"
return 1
fi
if [[ ! -x "${INSTALL_DIR}/lib/telegram.sh" ]]; then
error "telegram.sh не исполняемый"
return 1
fi
# ==================== LIB/EMAIL.SH ====================
cat > "${INSTALL_DIR}/lib/email.sh" << 'EMAILEOF'
#!/bin/bash
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"
source "$(dirname "$0")/utils.sh"
encode_email_header() {
local text="$1"
echo "$text" | tr -d '\r\n' | sed 's/"/\\"/g'
}
send_email() {
local subj="$1" body="$2" att="${3:-}"
[[ "$EMAIL_ENABLED" != "true" ]] && return 0
[[ -z "$GMAIL_USER" || -z "$GMAIL_APP_PASSWORD" ]] && return 1
[[ -z "$EMAIL_RECIPIENTS" ]] && return 1
command -v base64 &>/dev/null || { log "ERROR" "base64 не найден"; return 1; }
local cmd=""
command -v mutt &>/dev/null && cmd="mutt" || command -v mail &>/dev/null && cmd="mail" || return 1
ensure_tmp_dir || return 1
local tmp
tmp=$(safe_mktemp "${TMP_DIR}/email_XXXXXX.tmp")
[[ -z "$tmp" ]] && { log "ERROR" "Не удалось создать tmp"; return 1; }
local encoded_subj
encoded_subj=$(encode_email_header "$subj")
{
echo "From: StealthNet <${GMAIL_USER}>"
echo "To: ${EMAIL_RECIPIENTS}"
echo "Subject: ${encoded_subj}"
echo "MIME-Version: 1.0"
if [[ -n "$att" && -f "$att" ]]; then
local bn bc
bn=$(basename "$att")
bc="backup-$(date +%s)"
echo "Content-Type: multipart/mixed; boundary=\"${bc}\""
echo ""
echo "--${bc}"
echo "Content-Type: text/plain; charset=UTF-8"
echo ""
echo "$body"
echo ""
echo "--${bc}"
echo "Content-Type: application/gzip; name=\"${bn}\""
echo "Content-Disposition: attachment; filename=\"${bn}\""
echo "Content-Transfer-Encoding: base64"
echo ""
base64 "$att"
echo ""
echo "--${bc}--"
else
echo "Content-Type: text/plain; charset=UTF-8"
echo ""
echo "$body"
fi
} > "$tmp"
set +x
if [[ "$cmd" == "mutt" ]]; then
[[ -n "$att" && -f "$att" ]] && timeout 60 cat "$tmp" | mutt -s "$subj" -a "$att" -- $EMAIL_RECIPIENTS \
|| timeout 60 cat "$tmp" | mutt -s "$subj" -- $EMAIL_RECIPIENTS
else
[[ -n "$att" && -f "$att" ]] && timeout 60 cat "$tmp" | mail -s "$subj" -A "$att" $EMAIL_RECIPIENTS \
|| timeout 60 cat "$tmp" | mail -s "$subj" $EMAIL_RECIPIENTS
fi
rm -f "$tmp"
log "INFO" "Email отправлен: $EMAIL_RECIPIENTS"
}
send_backup_email() {
local status="$1" bf="$2" dur="$3" sz="$4" err="${5:-}"
local hn ts subj
hn=$(hostname)
ts=$(date '+%Y-%m-%d %H:%M:%S')
[[ "$status" == "success" ]] && subj="✅ Бэкап успешен - ${hn}" || subj="❌ Ошибка бэкапа - ${hn}"
local body="Отчет бэкапа StealthNet
================================
Сервер: ${hn} | Дата: ${ts} | Статус: ${status^^}
Файл: $(basename "$bf") | Размер: $(human_readable_size "$sz") | Длительность: ${dur}с"
[[ "$status" == "failed" ]] && body="${body}
ОШИБКА: ${err}"
local att=""
if [[ "$status" == "success" && -f "$bf" && $sz -lt ${EMAIL_MAX_ATTACH_MB:-24} ]]; then
att="$bf"
elif [[ "$status" == "success" ]]; then
body="${body}
ПРИМЕЧАНИЕ: Файл слишком большой для вложения."
fi
send_email "$subj" "$body" "$att"
}
EMAILEOF
if [[ ! -f "${INSTALL_DIR}/lib/email.sh" ]]; then
error "Не удалось создать email.sh"
return 1
fi
if ! chmod +x "${INSTALL_DIR}/lib/email.sh" 2>/dev/null; then
error "Не удалось установить права на email.sh"
return 1
fi
if [[ ! -x "${INSTALL_DIR}/lib/email.sh" ]]; then
error "email.sh не исполняемый"
return 1
fi
# ==================== BACKUP.SH ====================
cat > "${INSTALL_DIR}/backup.sh" << 'BACKUPEOF'
#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/telegram.sh"
source "${SCRIPT_DIR}/lib/email.sh"
send_notifications_with_timeout() {
local status="$1" file="$2" dur="$3" size="$4" err="${5:-}"
(
send_backup_notification "$status" "$file" "$dur" "$size" "$err"
send_backup_email "$status" "$file" "$dur" "$size" "$err"
) &
local pid=$!
local timeout="${NOTIFICATION_TIMEOUT:-${NOTIFICATION_TIMEOUT_DEFAULT:-60}}"
local count=0
while [[ $count -lt $timeout ]]; do
if ! kill -0 $pid 2>/dev/null; then
wait $pid 2>/dev/null || true
return 0
fi
sleep 1
((count++))
done
kill -TERM $pid 2>/dev/null || true
wait $pid 2>/dev/null || true
log "WARN" "Уведомления превысили таймаут (${timeout}с)"
}
pg_dump_with_auth() {
timeout 300 docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
pg_dump -U "$DB_USER" -d "$DB_NAME" "$@"
return $?
}
main() {
local btype="${1:-daily}"
local st bf="" cf="" sz=0 dur=0
st=$(date +%s)
log "INFO" "=== Запуск ${btype} бэкапа ==="
check_root
check_docker
check_required_vars
ensure_tmp_dir || exit 1
if [[ ! -d "$BACKUP_DIR" ]]; then
mkdir -p "$BACKUP_DIR" || { log "ERROR" "Не удалось создать $BACKUP_DIR"; exit 1; }
fi
check_disk_space "$BACKUP_DIR" "${MIN_DISK_SPACE_KB:-1048576}" || exit 1
acquire_lock || exit 1
log "INFO" "БД: ${DB_NAME}@${DB_CONTAINER}"
bf=$(get_backup_path "$btype")
if [[ -z "$bf" ]]; then
log "ERROR" "Не удалось получить путь для бэкапа"
exit 1
fi
log "INFO" "Цель: ${bf}"
log "INFO" "Запуск pg_dump..."
set +x
local ec=0
if ! pg_dump_with_auth -Fp --no-owner --no-acl --clean --if-exists > "$bf" 2>"${TMP_DIR}/pgerr.$$"; then
ec=$?
fi
if [[ $ec -ne 0 ]]; then
local em
em=$(cat "${TMP_DIR}/pgerr.$$" 2>/dev/null || echo "")
[[ -z "$em" ]] && em="pg_dump код $ec"
log "ERROR" "pg_dump ошибка: $em"
rm -f "$bf" "${TMP_DIR}/pgerr.$$"
send_notifications_with_timeout "failed" "$bf" 0 0 "$em"
exit 1
fi
rm -f "${TMP_DIR}/pgerr.$$"
if [[ ! -s "$bf" ]]; then
log "ERROR" "Пустой бэкап"
send_notifications_with_timeout "failed" "$bf" 0 0 "Пустой файл"
exit 1
fi
log "INFO" "Сжатие..."
cf="${bf}.gz"
if ! gzip -${COMPRESSION_LEVEL} -c "$bf" > "$cf"; then
log "ERROR" "Сжатие не удалось, сохраняю несжатый дамп"
rm -f "$cf"
send_notifications_with_timeout "failed" "$bf" 0 0 "gzip error"
exit 1
fi
if ! gzip -t "$cf" 2>/dev/null; then
log "ERROR" "Gzip архив поврежден"
rm -f "$cf"
send_notifications_with_timeout "failed" "$bf" 0 0 "archive corrupted"
exit 1
fi
rm -f "$bf"
sz=$(get_file_size_mb "$cf")
dur=$(( $(date +%s) - st ))
log "INFO" "Создан: ${cf} | Размер: $(human_readable_size "$sz") | Время: ${dur}с"
ln -sf "$cf" "${BACKUP_DIR}/latest-backup.sql.gz"
update_backup_index
send_notifications_with_timeout "success" "$cf" "$dur" "$sz"
"${SCRIPT_DIR}/cleanup.sh" "$btype"
log "INFO" "Завершено"
exit 0
}
update_backup_index() {
local idx="${BACKUP_DIR}/backup-index.json"
local tmp
tmp=$(safe_mktemp "${TMP_DIR}/idx_XXXXXX.json")
[[ -z "$tmp" ]] && { log "ERROR" "Не удалось создать tmp"; return 1; }
local items="" first=true
while IFS= read -r ln; do
local ep="${ln%% *}" fp="${ln#* }"
[[ -z "$fp" ]] && continue
local fn rp sz fd
fn=$(basename "$fp")
rp=${fp#$BACKUP_DIR/}
sz=$(stat -c%s "$fp" 2>/dev/null || echo 0)
fd=$(date -d @"${ep%.*}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
local rpe fne fde sh
rpe=$(escape_json "$rp")
fne=$(escape_json "$fn")
fde=$(escape_json "$fd")
sh=$(human_readable_size $((sz/1024/1024)))
[[ "$first" == "true" ]] && first=false || items="${items},"
items="${items}
{\"path\":\"${rpe}\",\"filename\":\"${fne}\",\"date\":\"${fde}\",\"size\":${sz},\"size_human\":\"${sh}\"}"
done < <(find "$BACKUP_DIR" -name "*.sql.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -${BACKUP_INDEX_LIMIT:-100})
if command -v jq &>/dev/null; then
jq -n --arg gen "$(date -Iseconds)" --argjson items "[$items]" '{generated:$gen,backups:$items}' > "$tmp" 2>/dev/null
else
{
echo "{"
echo "  \"generated\": \"$(date -Iseconds)\","
[[ -z "$items" ]] && echo "  \"backups\": []" || { echo "  \"backups\": [$items"; echo "  ]"; }
echo "}"
} > "$tmp"
fi
mv "$tmp" "$idx"
}
[[ "${1:-}" == "--update-index-only" ]] && { update_backup_index; exit 0; }
main "$@"
BACKUPEOF
if [[ ! -f "${INSTALL_DIR}/backup.sh" ]]; then
error "Не удалось создать backup.sh"
return 1
fi
if ! chmod +x "${INSTALL_DIR}/backup.sh" 2>/dev/null; then
error "Не удалось установить права на backup.sh"
return 1
fi
if [[ ! -x "${INSTALL_DIR}/backup.sh" ]]; then
error "backup.sh не исполняемый"
return 1
fi
# ==================== RESTORE.SH ====================
cat > "${INSTALL_DIR}/restore.sh" << 'RESTOREEOF'
#!/bin/bash
set -uo pipefail
if [[ -z "${BASH_VERSINFO[0]:-}" ]] || (( BASH_VERSINFO[0] < 4 )); then
echo "Требуется Bash 4+" >&2
exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/utils.sh"
TMP_SQL=""
PGPASS_FILE=""
cleanup_restore() {
[[ -n "$PGPASS_FILE" && -f "$PGPASS_FILE" ]] && rm -f "$PGPASS_FILE"
[[ -n "$TMP_SQL" && -f "$TMP_SQL" ]] && rm -f "$TMP_SQL"
timeout 10 docker exec "$DB_CONTAINER" rm -f "/tmp/.pgpass" > /dev/null 2>&1 || true
}
trap 'cleanup_restore; exit $?' EXIT INT TERM QUIT HUP
show_help() {
cat << EOF
Использование: $0 <источник> [опции]
Источники: latest | <путь> | @YYYY-MM-DD
Опции: --force/-f (без подтверждения), --create-before (бэкап перед)
EOF
}
confirm_restore() {
echo -e "${RED}ВНИМАНИЕ: Это УНИЧТОЖИТ базу данных '${DB_NAME}'!${NC}"
local att=3
while [[ $att -gt 0 ]]; do
echo -ne "Введите 'RESTORE' для подтверждения: "
if [[ -t 0 ]]; then
read -r cf
else
read -r cf < /dev/tty
fi
if [[ -z "$cf" ]]; then
((att--))
[[ $att -gt 0 ]] && echo "Попыток: $att" || { echo "Отменено"; exit 0; }
continue
fi
local confirm_upper
confirm_upper=$(printf '%s' "$cf" | LC_ALL=C tr 'a-z' 'A-Z')
if [[ "$confirm_upper" == "RESTORE" ]]; then
return 0
else
((att--))
[[ $att -gt 0 ]] && echo "Попыток: $att" || { echo "Отменено"; exit 0; }
fi
done
}
find_backup_by_date() {
local td="$1" bf="" md=999999999
while IFS= read -r f; do
[[ -z "$f" ]] && continue
local fd=""
if [[ "$f" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}) ]]; then
fd="${BASH_REMATCH[1]}"
fi
if [[ -n "$fd" ]]; then
local fe te df
fe=$(date -d "${fd//_/-}" +%s 2>/dev/null || echo 0)
te=$(date -d "$td" +%s 2>/dev/null || echo 0)
df=$((fe-te))
[[ ${df#-} -lt $md ]] && { md=${df#-}; bf="$f"; }
fi
done < <(find "$BACKUP_DIR" -name "*.sql.gz" -type f 2>/dev/null)
[[ -n "$bf" ]] && echo "$bf" || return 1
}
sanitize_backup_path() {
local path="$1"
local real_backup_dir
if [[ -z "$BACKUP_DIR" ]] || [[ "$BACKUP_DIR" == "/" ]] || [[ ! -d "$BACKUP_DIR" ]]; then
echo ""
return 1
fi
real_backup_dir=$(realpath -e "$BACKUP_DIR" 2>/dev/null) || { echo ""; return 1; }
if [[ "$path" == /* ]]; then
local real_path
real_path=$(realpath -m "$path" 2>/dev/null) || { echo ""; return 1; }
if [[ "$real_path" != "${real_backup_dir}/"* ]] && [[ "$real_path" != "${real_backup_dir}" ]]; then
echo ""
return 1
fi
echo "$real_path"
return 0
fi
local full_path="${BACKUP_DIR}/${path}"
local real_path
real_path=$(realpath -m "$full_path" 2>/dev/null) || { echo ""; return 1; }
if [[ "$real_path" != "${real_backup_dir}/"* ]] && [[ "$real_path" != "${real_backup_dir}" ]]; then
echo ""
return 1
fi
echo "$real_path"
return 0
}
restore_backup() {
local bs="$1" force=false cb=false
shift
while [[ $# -gt 0 ]]; do
case "$1" in
--force|-f) force=true ;;
--create-before) cb=true ;;
--help|-h) show_help; exit 0 ;;
esac
shift
done
check_root
check_docker
check_required_vars
ensure_tmp_dir || exit 1
local bf=""
case "$bs" in
latest)
bf=$(readlink -f "${BACKUP_DIR}/latest-backup.sql.gz" 2>/dev/null || true)
;;
@*)
bf=$(find_backup_by_date "${bs#@}")
;;
/*|./*)
local sanitized
sanitized=$(sanitize_backup_path "$bs")
if [[ -z "$sanitized" ]]; then
log "ERROR" "Небезопасный путь: $bs"
exit 1
fi
bf=$(realpath "$sanitized" 2>/dev/null || echo "$sanitized")
;;
*)
bf="${BACKUP_DIR}/${bs}"
;;
esac
if [[ ! -f "$bf" ]]; then
log "ERROR" "Не найден: $bf"
exit 1
fi
if ! verify_backup_path "$bf"; then
log "ERROR" "Файл вне директории бэкапов: $bf"
exit 1
fi
log "INFO" "Файл: $bf"
[[ "$cb" == "true" ]] && "${SCRIPT_DIR}/backup.sh" "pre-restore"
[[ "$force" != "true" ]] && confirm_restore
log "INFO" "Проверка подключения к БД..."
if ! timeout 30 docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null; then
log "ERROR" "Невозможно подключиться к БД. Проверьте учётные данные."
exit 1
fi
TMP_SQL=$(safe_mktemp "${TMP_DIR}/restore_XXXXXX.sql")
[[ -z "$TMP_SQL" ]] && { log "ERROR" "Не удалось создать tmp"; exit 1; }
mkdir -p "$TMP_DIR"
log "INFO" "Подготовка..."
[[ "$bf" == *.gz ]] && gunzip -c "$bf" > "$TMP_SQL" || cp "$bf" "$TMP_SQL"
if ! sed -i.bak '/^SET transaction_timeout/d' "$TMP_SQL" 2>/dev/null; then
log "WARN" "Не удалось удалить SET transaction_timeout"
fi
rm -f "${TMP_SQL}.bak" 2>/dev/null || true
log "INFO" "Очистка схемы..."
set +x
if ! timeout 60 docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" <<-EOF; then
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO public;
GRANT ALL ON SCHEMA public TO "$DB_USER";
EOF
log "ERROR" "Не удалось очистить схему"
exit 1
fi
log "INFO" "Восстановление..."
local psql_err
psql_err=$(timeout 300 docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 < "$TMP_SQL" 2>&1)
if [[ $? -ne 0 ]]; then
log "ERROR" "Ошибка восстановления: $psql_err"
rm -f "$TMP_SQL"
exit 1
fi
rm -f "$TMP_SQL"
log "INFO" "Восстановлено"
source "${SCRIPT_DIR}/lib/telegram.sh"
send_telegram_message "🔄 <b>БД восстановлена</b>
Сервер: <code>$(hostname)</code> | БД: <code>${DB_NAME}</code> | Источник: <code>$(basename "$bf")</code>"
}
[[ $# -eq 0 ]] && { show_help; exit 1; }
restore_backup "$@"
RESTOREEOF
if [[ ! -f "${INSTALL_DIR}/restore.sh" ]]; then
error "Не удалось создать restore.sh"
return 1
fi
if ! chmod +x "${INSTALL_DIR}/restore.sh" 2>/dev/null; then
error "Не удалось установить права на restore.sh"
return 1
fi
if [[ ! -x "${INSTALL_DIR}/restore.sh" ]]; then
error "restore.sh не исполняемый"
return 1
fi
# ==================== CLEANUP.SH ====================
cat > "${INSTALL_DIR}/cleanup.sh" << 'CLEANUPEOF'
#!/bin/bash
set -uo pipefail
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
source "${SCRIPT_DIR}/lib/utils.sh"
validate_retention() {
local v="$1" d="$2"
[[ ! "$v" =~ ^[0-9]+$ ]] || [[ "$v" -eq 0 ]] && echo "$d" || echo "$v"
}
cleanup_type="${1:-all}"
if [[ -z "$BACKUP_DIR" ]] || [[ ! -d "$BACKUP_DIR" ]]; then
log "ERROR" "BACKUP_DIR не задан или не существует"
exit 1
fi
if ! acquire_lock "$CLEANUP_LOCK_FILE"; then
log "WARN" "Другой процесс очистки уже выполняется"
exit 0
fi
RD=$(validate_retention "$RETENTION_DAILY" 7)
RW=$(validate_retention "$RETENTION_WEEKLY" 4)
RM=$(validate_retention "$RETENTION_MONTHLY" 12)
log "INFO" "Очистка ($cleanup_type)"
if [[ "$cleanup_type" == "all" || "$cleanup_type" == "daily" ]]; then
log "INFO" "Очистка ежедневных бэкапов (>${RD} дней)..."
find "$BACKUP_DIR" -name "*-daily-*.sql.gz" -type f -mtime +${RD} -delete 2>/dev/null || true
fi
if [[ "$cleanup_type" == "all" || "$cleanup_type" == "weekly" ]]; then
log "INFO" "Очистка еженедельных бэкапов (>${RW} недель)..."
find "$BACKUP_DIR" -name "*-weekly-*.sql.gz" -type f -mtime +$((RW*7)) -delete 2>/dev/null || true
fi
if [[ "$cleanup_type" == "all" || "$cleanup_type" == "monthly" ]]; then
log "INFO" "Очистка ежемесячных бэкапов (>${RM} месяцев)..."
find "$BACKUP_DIR" -name "*-monthly-*.sql.gz" -type f -mtime +$((RM*30)) -delete 2>/dev/null || true
fi
find "$BACKUP_DIR" -type d -empty -delete 2>/dev/null || true
total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
file_count=$(find "$BACKUP_DIR" -name "*.sql.gz" 2>/dev/null | wc -l)
log "INFO" "Готово. Файлов: $file_count | Размер: $total_size"
"${SCRIPT_DIR}/backup.sh" --update-index-only 2>/dev/null || true
release_lock
CLEANUPEOF
if [[ ! -f "${INSTALL_DIR}/cleanup.sh" ]]; then
error "Не удалось создать cleanup.sh"
return 1
fi
if ! chmod +x "${INSTALL_DIR}/cleanup.sh" 2>/dev/null; then
error "Не удалось установить права на cleanup.sh"
return 1
fi
if [[ ! -x "${INSTALL_DIR}/cleanup.sh" ]]; then
error "cleanup.sh не исполняемый"
return 1
fi
# ==================== SCHEDULER.SH ====================
cat > "${INSTALL_DIR}/scheduler.sh" << 'SCHEDULEREOF'
#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.env"
CRON_FILE="/etc/cron.d/stealthnet-backup"
install_scheduler() {
mkdir -p /etc/cron.d || { echo "Ошибка: /etc/cron.d" >&2; return 1; }
rm -f "$CRON_FILE"
cat > "$CRON_FILE" << EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
${SCHEDULE_DAILY} root ${SCRIPT_DIR}/backup.sh daily >> ${SCRIPT_DIR}/logs/cron-daily.log 2>&1
${SCHEDULE_WEEKLY} root ${SCRIPT_DIR}/backup.sh weekly >> ${SCRIPT_DIR}/logs/cron-weekly.log 2>&1
${SCHEDULE_MONTHLY} root ${SCRIPT_DIR}/backup.sh monthly >> ${SCRIPT_DIR}/logs/cron-monthly.log 2>&1
0 5 * * 0 root find ${SCRIPT_DIR}/logs -name "*.log" -mtime +30 -delete
EOF
chmod 644 "$CRON_FILE"
[[ -n "$(tail -c1 "$CRON_FILE" 2>/dev/null)" ]] && echo "" >> "$CRON_FILE"
if command -v systemctl >/dev/null 2>&1; then
systemctl restart cron || { echo "Ошибка при перезапуске cron через systemctl" >&2; return 1; }
else
service cron restart 2>/dev/null || /etc/init.d/cron restart || { echo "Ошибка при перезапуске cron" >&2; return 1; }
fi
echo "Планировщик установлен"
echo "  Ежедневно: $SCHEDULE_DAILY"
echo "  Еженедельно: $SCHEDULE_WEEKLY"
echo "  Ежемесячно: $SCHEDULE_MONTHLY"
}
remove_scheduler() {
rm -f "$CRON_FILE"
command -v systemctl >/dev/null 2>&1 && systemctl restart cron || true
service cron restart 2>/dev/null || /etc/init.d/cron restart || true
echo "Удалено"
}
case "${1:-install}" in
install) install_scheduler ;;
remove) remove_scheduler ;;
status) [[ -f "$CRON_FILE" ]] && cat "$CRON_FILE" || echo "Не установлен" ;;
*) echo "Использование: $0 [install|remove|status]" ;;
esac
SCHEDULEREOF
if [[ ! -f "${INSTALL_DIR}/scheduler.sh" ]]; then
error "Не удалось создать scheduler.sh"
return 1
fi
if ! chmod +x "${INSTALL_DIR}/scheduler.sh" 2>/dev/null; then
error "Не удалось установить права на scheduler.sh"
return 1
fi
if [[ ! -x "${INSTALL_DIR}/scheduler.sh" ]]; then
error "scheduler.sh не исполняемый"
return 1
fi
info "Скрипты созданы"
return 0
}
# ============================================
# Настройка logrotate
# ============================================
install_logrotate() {
info "Настройка logrotate..."
cat > /etc/logrotate.d/stealthnet-backup << EOF
${INSTALL_DIR}/logs/*.log {
daily
rotate 14
compress
delaycompress
missingok
notifempty
create 0640 root root
}
EOF
info "Logrotate настроен"
}
# ============================================
# Установка планировщика
# ============================================
install_scheduler() {
[[ "$INSTALL_SCHEDULE" != "true" ]] && { info "Пропуск планировщика"; return 0; }
info "Установка планировщика..."
"${INSTALL_DIR}/scheduler.sh" install
}
# ============================================
# Тестирование конфигурации
# ============================================
test_configuration() {
info "Тестирование..."
set +x
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${DB_CONTAINER}$"; then
warn "Контейнер '$DB_CONTAINER' не найден"
docker ps --format '  - {{.Names}}' 2>/dev/null
echo ""
local pc=""
while read -r n; do
timeout 10 docker exec "$n" pg_isready &>/dev/null && { pc="$n"; break; }
done < <(docker ps --format '{{.Names}}' 2>/dev/null || true)
if [[ -n "$pc" ]]; then
info "Найден: $pc"
if confirm "Использовать?" "д"; then
DB_CONTAINER="$pc"
sed -i.bak "s/DB_CONTAINER=.*/DB_CONTAINER=\"${DB_CONTAINER}\"/" "${INSTALL_DIR}/config.env"
rm -f "${INSTALL_DIR}/config.env.bak" 2>/dev/null || true
info "Обновлено"
fi
fi
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${DB_CONTAINER}$"; then
confirm "Продолжить без проверки?" "н" || return 1
fi
else
if timeout 30 docker exec "$DB_CONTAINER" pg_isready &>/dev/null || timeout 30 docker exec "$DB_CONTAINER" psql --version &>/dev/null; then
info "PostgreSQL готов: $DB_CONTAINER"
else
warn "PostgreSQL не отвечает"
fi
fi
info "Проверка подключения..."
if timeout 30 docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;" &>/dev/null; then
info "Подключение успешно"
else
warn "Не удалось подключиться"
confirm "Продолжить?" "н" || return 1
fi
if [[ "$TELEGRAM_ENABLED" == "true" ]]; then
info "Тест Telegram..."
set +x
local tm="🧪 <b>Тест StealthNet</b>
Сервер: $(hostname) | Время: $(date '+%Y-%m-%d %H:%M:%S')"
if timeout 30 curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
-d "chat_id=${TELEGRAM_CHAT_ID}" \
-d "text=${tm}" \
-d "parse_mode=HTML" \
--max-time 10 &>/dev/null; then
info "Telegram OK"
else
warn "Telegram ошибка"
fi
fi
echo ""
if confirm "Тестовый бэкап?" "д"; then
echo ""
"${INSTALL_DIR}/backup.sh" "test"
fi
return 0
}
# ============================================
# Показ итоговой информации
# ============================================
show_summary() {
echo ""
echo "========================================"
info "Установка завершена!"
echo "========================================"
echo ""
echo "Установка: ${INSTALL_DIR}"
echo "Бэкапы: ${BACKUP_DIR}"
echo "Контейнер: ${DB_CONTAINER}"
echo ""
echo "Команды:"
echo "  ${INSTALL_DIR}/backup.sh [daily|weekly|monthly]  # Бэкап"
echo "  ${INSTALL_DIR}/restore.sh latest                 # Восстановить последний"
echo "  ${INSTALL_DIR}/restore.sh <путь>                 # Восстановить файл"
echo "  ${INSTALL_DIR}/cleanup.sh                        # Очистка"
echo "  ${INSTALL_DIR}/scheduler.sh [install|remove]   # Планировщик"
echo ""
echo "Конфиг: ${INSTALL_DIR}/config.env"
echo ""
if [[ "$INSTALL_SCHEDULE" == "true" ]]; then
echo "Авто-бэкапы:"
echo "  Ежедневно: ${SCHEDULE_DAILY}"
echo "  Еженедельно: ${SCHEDULE_WEEKLY}"
echo "  Ежемесячно: ${SCHEDULE_MONTHLY}"
else
echo "Авто-бэкапы: отключены"
echo "Запуск: ${INSTALL_DIR}/backup.sh daily"
fi
echo ""
echo "Логи: ${INSTALL_DIR}/logs/"
echo ""
}
# ============================================
# Главная функция
# ============================================
main() {
check_root || exit 1
check_system || exit 1
check_and_install_tools || exit 1
check_existing_installation
local res=$?
[[ $res -eq 2 ]] && exit 0
echo ""
configure_panel || exit 1
echo ""
configure_database || exit 1
echo ""
configure_telegram || exit 1
echo ""
configure_email || exit 1
echo ""
configure_retention || exit 1
echo ""
configure_schedule || exit 1
echo ""
configure_paths || exit 1
echo ""
info "Настройки:"
echo "----------------------------------------"
echo "Панель: ${PANEL_DIR}"
echo "Установка: ${INSTALL_DIR}"
echo "Бэкапы: ${BACKUP_DIR}"
echo "Контейнер: ${DB_CONTAINER}"
echo "БД: ${DB_NAME}@${DB_USER}"
echo "Telegram: ${TELEGRAM_ENABLED} (Chat: ${TELEGRAM_CHAT_ID})"
echo "Email: ${EMAIL_ENABLED}"
echo "Хранение: ${RETENTION_DAILY}д/${RETENTION_WEEKLY}н/${RETENTION_MONTHLY}м"
[[ "$INSTALL_SCHEDULE" == "true" ]] && echo "Расписание: ${SCHEDULE_DAILY} / ${SCHEDULE_WEEKLY} / ${SCHEDULE_MONTHLY}"
echo "----------------------------------------"
echo ""
confirm "Продолжить?" "д" || { info "Отменено"; exit 0; }
install_dependencies || exit 1
create_directories || exit 1
generate_scripts || exit 1
install_logrotate
install_scheduler
test_configuration
show_summary
exit 0
}
main "$@"
