# Деплой на VPS

## Источник кода

Код для деплоя берётся **только из публичного репо**:
`https://github.com/acidmsg/lenreg-ticket-bot.git` (ветка `main`)

## Параметры подключения

См. [`.roo/rules/vps.md`](.roo/rules/vps.md) и [`.roo/rules/.env`](.roo/rules/.env).

```powershell
ssh -i C:/Users/acidgrip/.ssh/vps_lenreg_ticket_nopass -p 2244 root@195.58.39.52
```

Проект на VPS: `/srv/bots/lenreg-ticket-bot`

## Процедура деплоя

### 1. Остановка

```bash
cd /srv/bots/lenreg-ticket-bot
docker compose down
```

### 2. Очистка старых файлов (кроме .env и data/)

```bash
find . -mindepth 1 -maxdepth 1 ! -name '.env' ! -name 'data' -exec rm -rf {} \;
```

### 3. Клонирование публичного репо

```bash
git clone https://github.com/acidmsg/lenreg-ticket-bot.git /tmp/lenreg-fresh
cp -r /tmp/lenreg-fresh/* /srv/bots/lenreg-ticket-bot/
cp -r /tmp/lenreg-fresh/.[!.]* /srv/bots/lenreg-ticket-bot/ 2>/dev/null || true
rm -rf /tmp/lenreg-fresh
```

### 4. Сборка и запуск

```bash
docker compose up -d --build
```

### 5. Проверка

```bash
sleep 5
docker compose ps
docker compose logs --tail=20
```

## Чистая установка (сброс БД)

Если нужно развернуть проект с нуля (пустая БД, нет старых данных):

```bash
cd /srv/bots/lenreg-ticket-bot
docker compose down
rm -rf data/
docker compose up -d --build
```

Или через установочный скрипт (предпочтительно):

```bash
bash scripts/install.sh --clean
```

## Что попадает на VPS

**Только** файлы из публичного репо:

- `src/` — исходный код
- `locales/` — файлы локализации
- `scripts/` — скрипты (backup, restore, healthcheck, seed)
- `Dockerfile`, `docker-compose.yml` — инфраструктура
- `README.md`, `pyproject.toml`, `poetry.lock`, `.env.example` — метаданные
- `.dockerignore`, `.gitattributes` — конфиги сборки

**Плюс** сохраняемые с предыдущего деплоя:

- `.env` — конфиденциальные настройки (НЕ в образе, только `env_file`)
- `data/` — база данных SQLite (bind-mount `./data:/app/data`, переживает пересборку)

## Что НЕ попадает на VPS

Никакие dev-файлы: `.roo/`, `.agents/`, `specs/`, `tests/`, `_design_lab/`, `plans/`, `artifacts/`, CI/CD, конфиги линтеров.
