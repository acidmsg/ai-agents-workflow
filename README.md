# AI Agents Workflow

Автономная мультиагентная система разработки: от задачи в Linear до Pull Request в GitHub — без участия человека.

## Как устроено

1. **Linear** — постановка задач (Epic → Issues)
2. **n8n** — оркестрация: декомпозиция, маршрутизация, алерты
3. **OpenClaw + DeepSeek** — написание кода
4. **Antigravity + Claude** — ревью кода
5. **GitHub** — изоляция веток, Pull Requests
6. **Zoo Code** — ручное ревью и merge

## Документация

- [Архитектура](docs/architecture.md) — роли, state machine, VPS-инфраструктура
- [План реализации](docs/implementation-plan.md) — 6 фаз, от VPS до интеграционного тестирования
- [Анализ диалога с Gemini](docs/analysis/gemini-dialog-2026-07-10.md) — исходное обсуждение архитектуры

## Быстрый старт

См. [план реализации](docs/implementation-plan.md), Фаза 0.
