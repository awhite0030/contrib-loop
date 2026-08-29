# HANDOVER — система автоматических PR-контрибуций (полная документация)

Документ для ИИ-агента, принимающего систему. Всё проверено вживую; отмечено, что
проверено, а что нет. Дата снимка: 2026-08-30 (UTC+3), система в момент передачи
работает: 7 сессий Джулса в полёте по всем целям.

## 1. Что это и зачем

Цель владельца аккаунта `awhite0030` — стать заметным/ключевым контрибьютором в
выбранных open-source проектах. Google Jules (AI-агент, тариф Pro: 100 задач/24ч,
15 параллельно) чинит чужие issues на форках; автоматизация валидирует фиксы и
открывает PR в upstream от имени владельца. Джулс работает ОТ ИМЕНИ аккаунта
awhite0030 (так настроено пользователем): все PR/коммиты/комментарии приходят с
логином `awhite0030`, никаких ботов не видно. Исключение: тело форк-PR содержит
маркер `created automatically by Jules` — по нему автоматизация отличает работу
Джулса.

Две независимые петли:
1. **contrib-loop** (новая, PR-режим) — 7 целевых репо, где принимают внешние PR.
2. **prime-agent loop** (старая, Discussions-режим) — upstream
   PrimeIntellect-ai/prime-agent закрывает PR-ы и Issue от невоучтённых аккаунтов
   ботом за ~30 сек (см. их CONTRIBUTING.md: путь к вочингу только через
   Discussions). Петля постит разборы багов в Discussions.

## 2. Доступы и секреты

- Локальный `gh` CLI авторизован как awhite0030 (токен в keyring, scope:
  gist, read:org, repo, workflow). Из-под него всё читается/пишется.
- Секреты GitHub Actions (значения нечитаемы, добавлены владельцем вручную):
  - `JULES_API_KEY` — ключ Jules API (jules.google.com/settings) — в репо
    `contrib-loop` и в `prime-agent`.
  - `PAT` — classic PAT (repo+workflow). В contrib-loop выставлен автоматически
    через `gh secret set PAT --body "$(gh auth token)"` — это gh-токен CLI.
- Состояние петель — НЕ в файлах, а в **repository variables**: `STATE`
  (contrib-loop), `JULES_STATE` (prime-agent). Значения — компактный JSON,
  читаются: `gh api repos/<repo>/actions/variables/<NAME> --jq .value`.

## 3. Карта репозиториев

| Репо | Роль |
|---|---|
| `awhite0030/contrib-loop` (приватный) | Оркестратор PR-петли: конфиг, воркфлоу, скрипты, состояние `STATE` |
| `awhite0030/prime-agent` (публичный форк) | Discussion-петля; воркфлоу в `.github/workflows/`, скрипты в `.jules-loop/`; состояние `JULES_STATE` |
| `awhite0030/{tapflow,nanocoder,mteb,updatecli,OpenNutriTracker,kana-dojo,formae}` | Чистые форки целей — там Джулс открывает свои PR; наших файлов НЕТ |
| upstream-и (см. targets.json) | Оригиналы; туда открываются финальные PR |

### Файлы contrib-loop (все с ролью)

```
targets.json                  # ЕДИНСТВЕННЫЙ конфиг: цели, бюджеты, лейблы, ветки.
                              # Добавить/убрать репо = правка здесь (+2 файла ниже).
prompt_template.md            # Системная часть промпта Джулса (автономность,
                              # процесс фикса, обязательные секции PR-описания).
scripts/lib.sh                # Общие функции: конфиг (jq), state_get/set/prune
                              # (repo variable STATE), Jules API (создание сессии,
                              # опрос, sendMessage, approvePlan, sources), self_dispatch.
scripts/cycle.sh              # ГЛАВНЫЙ СЦЕНАРИЙ ОДНОГО ЦИКЛА (см. раздел 4).
scripts/validate_and_open_pr.sh  # Валидация форк-PR + открытие PR в upstream.
scripts/nudge.txt             # Текст автоответа зависшей сессии.
scripts/validate/<target>.sh  # Команды валидации конкретного проекта (запускаются
                              # и в промпте Джулса, и в CI оркестратора).
rules/<target>.md             # Дистиллят CONTRIBUTING проекта → в промпт Джулса.
.github/workflows/loop.yml    # Единственный воркфлоу: cycle → toolchain → validate
                              # → chain (самозапуск).
README.md                     # Краткая шпаргалка (русская).
```

### Файлы prime-agent (`.jules-loop/`)

```
prompt_template.txt           # Промпт Джулса (Discussions-режим).
scripts/pick_and_dispatch.sh  # reconcile + бюджет + дисковери Discussions + диспатч.
scripts/lib.sh                # Аналогично contrib-loop, но STATE_VAR=JULES_STATE.
scripts/publish.sh            # Черновик комментария + постинг в Discussion (кап 2/сутки) + мёрж форк-PR.
scripts/reject.sh             # Провал валидации: коммент с логом, закрытие PR.
scripts/repost.sh             # Ручной постинг черновика (jules-contribute.yml).
scripts/nudge.txt, directives.md (директивы владельца → в промпт), README.md.
.github/workflows/jules-loop.yml     # Триггеры: dispatch, cron 7 */2 * * *, PR closed (мёрж Джулса) → следующая задача.
.github/workflows/jules-validate.yml # PR opened (маркер Джулса) → validate → publish/reject.
.github/workflows/jules-contribute.yml # Ручной постинг черновика в Discussion.
```

На форке prime-agent ОТКЛЮЧЕНЫ workflow upstream-процесса (disable через API):
build-binaries, changelog-fragment, ci, contribution-gate, linear-ticket — иначе
гейт закрыл бы PR-ы Джулса и на форке. jules-воркфлоу — active.

## 4. Как работает цикл PR-петли (contrib-loop)

Запуск: `Actions → contrib loop → Run workflow` (или самозапуск, или cron
`13 * * * *` как резерв). Concurrency-группа `contrib-loop` сериализует прогоны.

`scripts/cycle.sh`, фазы:
1. **Загрузка конфига** `targets.json` → `/tmp`, **state** из repo variable `STATE`.
   Суточный ролловер: если `state.day != сегодня` → обнулить `dispatchedDay`/`prsDay`.
2. **Reconcile всех целей**: для каждой задачи в статусе `dispatched` опрашивается
   сессия Джулса `GET /v1alpha/sessions/{id}`:
   - `COMPLETED` с `outputs[].pullRequest.url` → статус `in_review` (форк-PR ждёт валидации);
   - `COMPLETED` без PR → `no_pr` (Джулс решил, что баг уже починен/не воспроизводится);
   - `FAILED` → `failed`;
   - `AWAITING_USER_FEEDBACK` → автоответ `sendMessage` текстом `scripts/nudge.txt`
     (до 3 раз, счётчик `nudges`; после третьего — `stuck`);
   - `AWAITING_PLAN_APPROVAL` → автоодобрение `:approvePlan`;
   - `QUEUED/PLANNING/IN_PROGRESS/PAUSED` дольше `session_timeout_hours` (6ч) → `stuck`.
3. **Выбор одной задачи на валидацию**: первая попавшаяся `in_review` без `upstreamPr`.
   Если найдена — диспетч новых задач в этом прогоне НЕ происходит (валидация важнее).
4. **Диспетч (если валидации нет)**: по каждой цели с соблюдением гвардов:
   - в этой цели нет сессии `dispatched` (сериальность на цель);
   - глобальный бюджет: `GET /v1alpha/sessions` → сессий за 24ч < `globals.daily_task_cap` (92);
   - `dispatchedDay[цель] < budget` и `prsDay[цель] < max_prs_per_day` из конфига;
   - **дисковери**: по каждому лейблу из конфига `gh issue list` (OR-семантика,
     результаты мерджатся `unique_by(.number)`), фильтры: без assignee, номер не в
     state (handled), минус exclude-лейблы; берётся **старейший**;
   - **клейм** (если `claim_comment: true`): комментарий `Picking this up - a fix
     will follow shortly.`; для kana-dojo (`claim_verify: true`) через 30 сек
     проверяется, что бот назначил `awhite0030`; если перехватили — статус
     `claim_lost`, цель пропущена;
   - синк форка (`merge-upstream` API), проверка `jules_sources_has` (если форк не
     подключён к Джулсу — WARNING в лог и пропуск цели);
   - **диспетч**: `POST /v1alpha/sessions` c `X-Goog-Api-Key`, payload:
     `prompt` (шаблон + issue body + комментарии + текст `scripts/validate/<target>.sh`
     + `rules/<target>.md`), `sourceContext: sources/github/<fork>`,
     `githubRepoContext.startingBranch` (для OpenNutriTracker — `develop`),
     `requirePlanApproval: false`, `automationMode: "AUTO_CREATE_PR"`;
   - запись задачи в state, инкремент `dispatchedDay`.
5. **Режим следующего шага** (в `$GITHUB_OUTPUT`):
   - `mode=validate` + `validate_target/issue/fork/branch` — если есть что валидировать;
   - `mode=watch` — есть задачи в полёте: воркфлоу **спит 10 минут** в конце прогона;
   - `mode=idle` — делать нечего (бюджеты/кандидаты исчерпаны).

Дальше воркфлоу `loop.yml`:
- при `validate`: ставит тулчейн цели (node22+corepack / go / uv / flutter —
  условия в `if` шагов), чекаутит голову форк-PR в `pr-tree`, запускает
  `scripts/validate_and_open_pr.sh`:
  - гоняет `scripts/validate/<target>.sh` в дереве PR;
  - успех → сборка тела upstream-PR: их PR-шаблон (если есть, тянется из
    `.github/pull_request_template.md` upstream) + секции `Root cause/Fix/Validation`
    из тела форк-PR (парсер на awk) + `Fixes #N`; для mteb тело обрезается до
    2000 символов (`max_pr_body_chars`);
  - `gh pr create -R <upstream> --base <base_branch> --head <fork_owner>:<branch>`;
  - неуспех → форк-PR закрывается, статус `validation_failed`.
- при `watch` или после валидации: шаг **Chain the next run** —
  `gh workflow run loop.yml` (самонаводящаяся цепочка). При `idle` самозапуска нет,
  дальше работает часовой cron.

Дальше по жизни upstream-PR: статус `pr_open`, в дайджесте видно мерж/ревью.
Автоответов на ревью НЕТ — это сознательно (см. раздел 9).

## 5. Как работает Discussion-петля (prime-agent)

Логика та же (reconcile → budget → дисковери Discussions категории Bug reports →
сессия на форке), отличие — финал: PR Джулса на форке валидируется
(`npm ci → npm run build → npm run check` + точечные регресс-тесты из диффа
командой из AGENTS.md), затем `publish.sh` собирает черновик комментария
(причина/фикс/валидация + ссылка на дифт форка), постит его в исходный Discussion
через GraphQL `addDiscussionComment` (лимит `JULES_MAX_POSTS`=2/сутки,
дедуп по `posted`), и мёржит форк-PR (`gh pr merge` → merge-событие запускает
следующую задачу — «общение через коммиты»). Провал валидации — `reject.sh`:
комментарий с хвостом лога, закрытие PR, статус `failed`.
Секреты: `JULES_API_KEY`, `PAT`; переменные: `JULES_DAILY_BUDGET`=20,
`JULES_MAX_POSTS`=2, `JULES_AUTOPOST`=true, `JULES_STATE`.

## 6. Состояние (схемы)

`STATE` (contrib-loop) и `JULES_STATE` (prime-agent) — одинаковая идея:
```json
{
  "day": "2026-08-30",                    // для суточных счётчиков
  "dispatchedDay": {"tapflow": 1},        // задач запущено сегодня по целям
  "prsDay": {"tapflow": 0},               // upstream-PR открыто сегодня
  "targets": {                            // в prime-agent поле называется "dispatched"/"posted"
    "tapflow": {
      "tasks": {"153": {"sessionId": "...", "ts": "...", "status": "dispatched",
                        "sessionUrl": "...", "nudges": 0,
                        "forkPr": "https://github.com/awhite0030/tapflow/pull/1",
                        "upstreamPr": "https://github.com/jo-duchan/tapflow/pull/N"}},
      "posted": {}                        // в prime-agent: {discussion: {ts, commentUrl}}
    }
  }
}
```
Статусы задачи: `dispatched → in_review → pr_open → merged`; ветки отказа:
`validation_failed`, `no_pr`, `failed`, `stuck`, `claim_lost`. Терминальные
статусы НЕ ретраятся автоматически (анти-зацикливание); повтор — вручную
(`target` + `issue` в dispatch, при override лимиты раздвигаются).
PR-е prime-agent параллельно трекаются в status полей того же формата.

## 7. Бюджеты (где менять)

- Глобально: `targets.json → globals.daily_task_cap` (92), проверка по реальному
  API Джулса (сессии за 24ч, включая ручные).
- На цель: `budget` (задач/сутки) и `max_prs_per_day` (upstream-PR/сутки).
  Философия: узкое место — ревью-пропускная способность мейнтейнеров, а не квота.
  Текущие: tapflow 4/3, nanocoder 4/3, mteb 4/3, updatecli 4/3,
  opennutritracker 2/2, kana-dojo 8/4, formae 2/1, prime-agent 20 (переменная
  `JULES_DAILY_BUDGET`) и 2 поста/сутки. Итого ~48 задач/сутки — сознательный
  запас; поднять = правка targets.json.

## 8. Jules API (как используется)

- `POST https://jules.googleapis.com/v1alpha/sessions`, заголовок
  `X-Goog-Api-Key: <JULES_API_KEY>`. Payload: `prompt`, `title`,
  `sourceContext: {source: "sources/github/<owner>/<repo>",
  githubRepoContext: {startingBranch}}`, `requirePlanApproval: false`,
  `automationMode: "AUTO_CREATE_PR"` (Джулс сам создаёт ветку и PR на форке).
- `GET /v1alpha/sessions?pageSize=100` — бюджет (createTime за 24ч) и список.
- `GET /v1alpha/sessions/{id}` — `state` (QUEUED/PLANNING/AWAITING_PLAN_APPROVAL/
  AWAITING_USER_FEEDBACK/IN_PROGRESS/PAUSED/FAILED/COMPLETED) и
  `outputs[].pullRequest.url`.
- `POST .../sessions/{id}:sendMessage {"prompt": ...}` — автоответ зависшим.
- `POST .../sessions/{id}:approvePlan` — од approve плана.
- `GET /v1alpha/sources` — форки, подключённые к Jules GitHub App.
- Нюансы: API alpha; сессии идут от имени пользователя; вопрос-паузы лечатся
  sendMessage; квота тарифа 100/24ч, 15 параллельно.

## 9. Эксплуатация (шпаргалка команд)

```bash
# запустить цикл / форс задачу
gh workflow run loop.yml --repo awhite0030/contrib-loop
gh workflow run loop.yml --repo awhite0030/contrib-loop -f target=tapflow -f issue=153

# логи последнего прогона
gh run view $(gh run list --repo awhite0030/contrib-loop --workflow loop.yml --limit 1 --json databaseId --jq '.[0].databaseId') --repo awhite0030/contrib-loop --log

# состояние
gh api repos/awhite0030/contrib-loop/actions/variables/STATE --jq .value | jq .
gh api repos/awhite0030/prime-agent/actions/variables/JULES_STATE --jq .value | jq .

# остаток квоты Джулса
# (считается в логе цикла: строка "budget: N/92") либо jules.google.com/settings

# остановить петли
gh api -X PUT repos/awhite0030/contrib-loop/actions/workflows/loop.yml/disable
gh api -X PUT repos/awhite0030/prime-agent/actions/workflows/jules-loop.yml/disable

# ручной постинг черновика в Discussion (prime-agent)
gh workflow run jules-contribute.yml --repo awhite0030/prime-agent -f discussion_number=N -f pr_number=M
```

Добавление цели: форк (`gh repo fork owner/repo --clone=false`) → запись в
`targets.json` → `rules/<id>.md` + `scripts/validate/<id>.sh` → при необходимости
добавить тулчейн-шаг в loop.yml → подключить форк в jules.google.com (если App
не на «all repositories»).

Ежедневный дайджест: автоматизация ZCode «Ежедневный дайджест контрибуций в
09:00» (id automation-66c3dce8) — читает STATE/JULES_STATE, статусы upstream-PR,
ответы мейнтейнеров, здоровье воркфлоу, докладывает в чат.

## 10. Известные грабли (уже закатанные, но помнить)

1. `jq -n` без `-r` при сборке ТЕКСТА даёт JSON-строку с литеральными `\n`
   (был битый комментарий в upstream #1707 — отредактирован вручную через
   `updateDiscussionComment`).
2. `gh issue list` с несколькими `--label` = AND; нужен OR → собирать по лейблам
   и мерджить (`add | unique_by(.number)`).
3. Комбинированный jq-фильтр с двумя `--argjson` на раннере (jq 1.7 linux)
   вернул пустоту, хотя на 1.7.1 (mac) работает; на раннере же по отдельности
   обе селекци работали. Разложено на два последовательных вызова. Мораль: на
   раннере проверять каждую jq-команду.
4. Кроны на форках ненадёжны (молчат даже при state=active) — основной механизм
   самозапуск каждого прогона, крон только резерв.
5. PyYAML на раннерах не гарантирован — конфиги только JSON.
6. `state_get` обязан возвращать `{}` и при отсутствии переменной, и при ошибке.
7. PR-ы Джулса приходят с логином пользователя; маркер для опознания —
   «created automatically by Jules» в теле.
8. У mteb лимит описания PR 2000 символов; у OpenNutriTracker PR только в
   `develop`; у kana-dojo первого комментатора бот назначает автоматически.
9. Скрипты петель никогда не пушат в main (состояние только в variables) — нет
   гонок и конфликтов при синке форков.

## 11. Статус на момент передачи

Проверено вживую:
- prime-agent: полный цикл ×2 (#1707, #1711 — session → PR → валидация → пост в
  Discussion → мёрж → цепочка), авто-нидж, автопостинг, капы, no_pr-ветка (#1695).
- contrib-loop: конфиг, дисковери по 7 целям (живые кандидаты), клейм kana-dojo
  и nanocoder, глобальный бюджет, STATE-переменная, самозапуск, watch-режим.
  **7 сессий диспетчены по всем 7 целям** (formae #39, kana-dojo #29401, mteb
  #1227, nanocoder #937, opennutritracker #79, tapflow #153, updatecli #559).

Не проверено ещё (произойдёт само ночью, увидит дайджест):
- валидационная фаза contrib-loop на реальном форк-PR (тулчейны, открытие
  upstream-PR) — код написан, но вживую не гонялся; первый прогон может вскрыть
  мелочи (пути, тулчейн-версии) — смотреть логи `loop.yml`, шаги
  `Validate and open upstream PR`;
- `no_pr`/`validation_failed`/`claim_lost` ветки contrib-loop;
- реакция мейнтейнеров (это уже не автоматизация).

Приоритет принимающему агенту: дождаться первых форк-PR (15–60 мин на сессию),
проследить фазу validate до появления upstream-PR в tapflow; починить по логам,
если что-то упадёт; дальше система в штатном режиме + дайджест в 09:00.
