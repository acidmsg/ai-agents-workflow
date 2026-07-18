# Архитектура автономной мультиагентной системы

## Распределение ролей

| Компонент         | Где                    | Модель                         | Роль                                           |
| ----------------- | ---------------------- | ------------------------------ | ---------------------------------------------- |
| Linear            | Cloud                  | —                              | State Machine (7 статусов), Epic/Issues        |
| n8n               | VPS (npm, n8n_user)    | DeepSeek-V4-Pro                | Оркестратор, декомпозиция                      |
| Hermes            | VPS (hermes_user)      | DeepSeek-V4-Flash              | Утилита n8n: нормализация, PR-описания, ошибки |
| OpenClaw          | VPS (openclaw_user)    | V4-Pro (код) / V4-Flash (bash) | Кодер                                          |
| Antigravity CLI   | VPS (antigravity_user) | Claude 4.6 (Google One)        | AI-критик                                      |
| GitHub            | Cloud                  | —                              | Шина данных: ветки, PR                         |
| Zoo Code + Qdrant | Home PC                | DeepSeek-V4-Pro                | Ручное ревью, RAG impact analysis              |

## Linear State Machine

Backlog → Todo → In Progress → In Testing → In Review → Done → Merged
In Progress → Needs Human Review (4 ретрая исчерпаны)
In Testing → In Progress (человек отклонил PR)

## Внутренний цикл (agent_loop.sh, внутри In Progress)

OpenClaw → Линтеры → Тесты → Antigravity (Claude 4.6) → git push + gh pr create
До 4 ретраев при reject от критика или падении линтеров/тестов.

## VPS: пользователи и права

- Пользователи: n8n_user, openclaw_user, antigravity_user, hermes_user
- Группа: ai-workers (все пользователи)
- Проекты: chown :ai-workers, chmod 2775 (SGID), umask 0002
- Линтеры: /usr/local/bin/{ruff,golangci-lint,eslint,stylelint,markdownlint}, chmod 755

## Секреты (гибридный подход)

/opt/secrets/
├── shared.env (640, :ai-workers) — DEEPSEEK_API_KEY, GITHUB_TOKEN
├── n8n.env (600) — LINEAR_API_KEY
├── openclaw.env (600)
├── antigravity.env (600) — ANTI_GRAVITY_TOKEN
└── hermes.env (600)

## Мульти-репо

Файл /opt/config/repo-map.json: маппинг Linear Project ID → repo_path.
Параллельно между репо, последовательно внутри одного.

## Мониторинг

n8n Error Trigger → Telegram.
Prometheus/Grafana отложены (VPS 4 ГБ RAM).

## Ключевые решения

1. OpenClaw (кодер) и Antigravity (критик) — строгое разделение ролей
2. Модель декомпозиции в n8n: DeepSeek-V4-Pro
3. Hermes — только утилита n8n, не в цикле кодинга
4. Тесты после линтеров, до AI-критика (skip если нет)
5. Зависимости Issues: n8n проверяет блокировки через Linear GraphQL
6. Откат PR: revert → n8n → новый Issue → цикл исправления
7. Live Preview: Remote SSH (primary) + Docker в agent_loop.sh (bonus)
