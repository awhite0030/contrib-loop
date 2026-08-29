# contrib-loop — мульти-репозиториальная петля PR-контрибуций

Управляющий центр автоматизации: Джулс чинит чужие issues на чистых форках,
валидация гоняет команды проекта, зелёные фиксы открываются как PR в upstream.

## Как добавить/убрать цель
Правка одной записи в `targets.yaml` (+ `rules/<id>.md` и `scripts/validate/<id>.sh`).
Форк создать: `gh repo fork <owner>/<repo> --clone=false`. Джулс должен видеть
форк (jules.google.com → GitHub connection, если App стоит не на «all repos»).

## Команды
- Запустить цикл: Actions → contrib loop → Run workflow
  (опционально `target` + `issue` — принудительная задача поверх лимитов)
- Состояние: переменная репо `STATE` (JSON: goals → tasks → статусы, дневные счётчики)
- Остановить всё: Actions → contrib loop → `...` → Disable workflow

## Статусы задач
`dispatched` (сессия в работе) → `in_review` (PR форка ждёт валидации) →
`pr_open` (PR в upstream) → `merged`/`validation_failed`/`no_pr`/`stuck`/`claim_lost`.

## Файлы
- `targets.yaml` — цели, бюджеты (задач/сутки), PR-лимиты, лейблы дисковери, ветки
- `scripts/cycle.sh` — reconcile + диспетч + часовой (сон 10 мин + самозапуск)
- `scripts/validate_and_open_pr.sh` — валидация PR форка → PR в upstream
- `scripts/validate/<id>.sh` — команды валидации конкретного проекта
- `rules/<id>.md` — дистиллят CONTRIBUTING проекта (попадает в промпт Джулса)
- `prompt_template.md` — системная часть промпта
- `scripts/nudge.txt` — автоответ зависшей сессии

## Бюджеты
Глобально ≤ 92 задач/сутки (`globals.daily_task_cap`), по целям — в конфиге.
PR-лимиты (`max_prs_per_day`) — защита от спама: узкое место не квота Джулса,
а способность мейнтейнеров ревьюить. Крон `13 * * * *` — резервная сетка;
основной ход — самозапуск каждого прогона.

Секреты: `JULES_API_KEY`, `PAT` (classic, scope repo+workflow).
