#!/bin/bash
# Checks sessync, its search, install.sh and uninstall.sh without a real storage: the "storage" is a
# local folder, each "Mac" is a set of folders instead of ~/.claude, ~/.config and ~/.local/state,
# secrets come from the environment. Doesn't touch the Keychain, the real ~/.claude or ~/.local/bin.
# Needs rclone, jq, python3. Most checks read the Russian interface (SESSYNC_LANG=ru), one section
# the English one.
#   tests/run.sh          (KEEP=1 — keep the temporary folder, for debugging)
set -u
here=$(cd "$(dirname "$0")/.." && pwd -P)
T=$(mktemp -d "${TMPDIR:-/tmp}/sessync-test.XXXXXX")
[ -n "${KEEP:-}" ] || trap 'rm -rf "$T"' EXIT; echo "T=$T"
export SESSYNC_TEST_REMOTE="$T/s3" SESSYNC_LANG=ru
export SESSYNC_TEST_S3_ACCESS_KEY=test SESSYNC_TEST_S3_SECRET_KEY=test
export SESSYNC_TEST_PASSPHRASE=correct-horse-battery-staple
# rclone storage: tests must not read the real ~/.config/rclone/rclone.conf
export RCLONE_CONFIG="$T/rclone-user.conf"; : > "$RCLONE_CONFIG"
mkdir -p "$T/s3/bucket"
fails=0

check() {  # check "description" command… — ok if the command succeeds
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $name"; else echo "FAIL  $name"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
setconf() { mkdir -p "$T/$1/config/sessync"; printf 'BUCKET=%s\n' "$2" > "$T/$1/config/sessync/config"; }
mac() {  # mac A — a "Mac" with default settings
  mkdir -p "$T/$1/projects"
  printf '{"cleanupPeriodDays": 36500}\n' > "$T/$1/settings.json"
  setconf "$1" bucket
}
ss() {  # ss A command… — sessync on "Mac" A
  local m=$1; shift
  CLAUDE_CONFIG_DIR="$T/$m" XDG_CONFIG_HOME="$T/$m/config" XDG_STATE_HOME="$T/$m/state" \
    XDG_CACHE_HOME="$T/$m/cache" SESSYNC_HOST="host$m" "$here/bin/sessync" "$@"
}
run() { ss "$@"; }
has() { local m=$1 pat=$2; shift 2; ss "$m" "$@" 2>&1 | grep -q -- "$pat"; }   # output contains
stf() { echo "$T/$1/state/sessync/$2"; }                                           # state file
at() {  # at A "commands" — with A's storage env (rclone remotes ss:, ssk:)
  CLAUDE_CONFIG_DIR="$T/$1" XDG_CONFIG_HOME="$T/$1/config" XDG_STATE_HOME="$T/$1/state" \
    bash -c "source '$here/bin/sessync' version >/dev/null; load_env && $2"
}
say() {  # say A project id text — append a conversation line to a session
  local f="$T/$1/projects/$2/$3.jsonl"
  mkdir -p "$(dirname "$f")"
  printf '{"type":"user","message":{"role":"user","content":"%s"},"cwd":"/tmp/%s","timestamp":"2026-10-10T10:00:%02dZ","sessionId":"%s"}\n' \
    "$4" "$2" "$((RANDOM % 60))" "$3" >> "$f"
}
lines() { wc -l < "$1" | tr -d ' '; }
contains() { grep -qF -- "$2" "$1"; }
absent() { ! grep -rqF -- "$2" "$1"; }

echo "== Первый Mac загружает, второй получает"
mac A; mac B
for i in 1 2 3 4; do say A -tmp-p1 "s$i" "привет из A номер $i"; done
say A -tmp-p1 s5 "уникальнаяфраза для поиска"
mkdir -p "$T/A/projects/-tmp-p1/memory" && echo "память A" > "$T/A/projects/-tmp-p1/memory/MEMORY.md"
mkdir -p "$T/A/projects/-tmp-p1/s1/tool-results"   # вложения сессий
for i in 1 2 3; do echo "вывод команды $i" > "$T/A/projects/-tmp-p1/s1/tool-results/r$i.txt"; done
echo '{"display":"промпт A","timestamp":1}' > "$T/A/history.jsonl"
echo '{"display":"промпт B","timestamp":2}' > "$T/B/history.jsonl"
check "A: первая синхронизация" run A now
check "в хранилище нет открытого текста" absent "$T/s3" "привет из A"
check "в хранилище нет открытых имён" absent "$T/s3" "-tmp-p1"
check "B: первая синхронизация" run B now
check "B получил сессии" test -f "$T/B/projects/-tmp-p1/s4.jsonl"
check "memory/ не синхронизируется" test ! -e "$T/B/projects/-tmp-p1/memory"
check "B получил вложения сессий" test -f "$T/B/projects/-tmp-p1/s1/tool-results/r3.txt"
check "B: история промптов объединена" contains "$T/B/history.jsonl" "промпт A"
run A now >/dev/null
check "A: история промптов объединена" contains "$T/A/history.jsonl" "промпт B"

echo "== Дописанное на одном Mac приходит на другой"
say B -tmp-p1 s1 "ответ с B"
check "B: отправка" run B now
check "A: получение" run A now
check "A: в s1 две строки" test "$(lines "$T/A/projects/-tmp-p1/s1.jsonl")" = 2
check "без изменений ничего не передаётся" has A 'отправлено файлов 0, получено 0' now

echo "== Одна сессия изменилась на обоих Mac"
say A -tmp-p1 s2 "коротко"
say B -tmp-p1 s2 "длинная версия с другого Mac, она длиннее"
run B now >/dev/null
run A now >/dev/null
check "под основным именем — более длинная версия" contains "$T/A/projects/-tmp-p1/s2.jsonl" "длинная версия"
check "другая версия сохранена копией" contains "$T/A/projects/-tmp-p1/s2.jsonl.conflict1" "коротко"
check "статус показывает конфликт" has A 'Конфликтов: 1' status
check "строка статуса показывает конфликт" has A 'конфликт 1' statusline
check "conflicts --delete убирает копию" run A conflicts --delete
check "копии больше нет" test ! -e "$T/A/projects/-tmp-p1/s2.jsonl.conflict1"

echo "== Защиты"
mac C
before=$(find "$T/s3" -type f | wc -l)
wrongpass() { SESSYNC_TEST_PASSPHRASE=wrong-password-123 ss C now; }
check "C с другим паролем: отказ" not wrongpass
check "C с другим паролем: причина названа" contains "$(stf C error)" "пароль шифрования не тот"
check "C с другим паролем: в хранилище ничего не записано" test "$(find "$T/s3" -type f | wc -l)" = "$before"
check "в контрольном файле — домашняя папка первого Mac" sh -c "$(declare -f at); T='$T' here='$here'; at A 'rclone cat ssk:keycheck' | grep -q '^home /'"
newer() { at A 'printf "cc-sync key check v1\nformat 9\n" | rclone rcat ssk:keycheck 2>/dev/null'; }
check "хранилище в формате новее: отказ" sh -c "$(declare -f at ss newer); T='$T' here='$here'; newer; ! ss A now"
check "хранилище в формате новее: причина названа" contains "$(stf A error)" "новее этой версии"
at A "printf 'cc-sync key check v1\nformat 2\nhome %s\n' \"\$HOME\" | rclone rcat ssk:keycheck 2>/dev/null"
check "после возврата формата — снова работает" run A now

echo "== Срок хранения исправляется сам, удалённое Claude Code возвращается из архива"
printf '{"model": "opus", "cleanupPeriodDays": 30}\n' > "$T/B/settings.json"
rm "$T/B/projects/-tmp-p1/s3.jsonl"   # так Claude Code чистит старые сессии при старте
check "B со сроком 30 дней: синхронизация проходит" run B now
check "срок поднят до 36500, остальное на месте" jq -e '.cleanupPeriodDays == 36500 and .model == "opus"' "$T/B/settings.json"
check "прежний settings.json сохранён" sh -c "ls '$T/B'/settings.json.bak-sessync-* >/dev/null"
check "удалённая сессия вернулась из архива" test -f "$T/B/projects/-tmp-p1/s3.jsonl"
check "в статусе — восстановление" has B 'с восстановлением' status
run A now >/dev/null
check "на другом Mac сессия тоже на месте" test -f "$T/A/projects/-tmp-p1/s3.jsonl"
mkdir -p "$T/D/projects"; setconf D bucket
check "новый Mac без settings.json: синхронизация проходит" run D now
check "новый Mac: срок хранения записан" jq -e '.cleanupPeriodDays == 36500' "$T/D/settings.json"
check "новый Mac: архив скачан" test -f "$T/D/projects/-tmp-p1/s3.jsonl"
mkdir -p "$T/E/projects"; printf '{"cleanupPeriodDays": 36500}\n' > "$T/E/settings.json"
check "E без настроек: отказ" not run E now
check "E: подсказка про setup" contains "$(stf E error)" "sessync setup"
check "выключение" run A off
check "выключено: синхронизация не идёт" has A 'выключена' now
check "выключено: видно в строке статуса" has A 'выкл' statusline
check "включение" run A on
check "строка статуса: время синхронизации" has A '↻' statusline

echo "== Корзина: удалённое хранится TRASH_DAYS и возвращается"
ln -s "$T/A/projects/-tmp-p1/s1.jsonl" "$T/A/projects/-tmp-p1/link.jsonl"   # как ссылки субагентов
run A now >/dev/null; run B now >/dev/null
check "ссылка приходит на другой Mac ссылкой" test -L "$T/B/projects/-tmp-p1/link.jsonl"
rm "$T/A/projects/-tmp-p1/s4.jsonl" "$T/A/projects/-tmp-p1/link.jsonl"
check "A: удаление синхронизируется" run A now
check "удалённая сессия — в корзине" has A 's4.jsonl' trash
run B now >/dev/null
check "на другом Mac она тоже удалена" test ! -e "$T/B/projects/-tmp-p1/s4.jsonl"
check "restore возвращает сессию" run B restore s4.jsonl
check "сессия вернулась целиком" contains "$T/B/projects/-tmp-p1/s4.jsonl" "привет из A номер 4"
check "restore возвращает ссылку ссылкой" sh -c "$(declare -f ss); T='$T' here='$here'; ss B restore link.jsonl && test -L '$T/B/projects/-tmp-p1/link.jsonl'"
check "restore: несуществующего нет" not run B restore нетакого
run B now >/dev/null; run A now >/dev/null
check "вернувшаяся сессия снова на другом Mac" test -f "$T/A/projects/-tmp-p1/s4.jsonl"
say A -tmp-p1 s7 "давно удалённая"
run A now >/dev/null
rm "$T/A/projects/-tmp-p1/s7.jsonl"
past() { SESSYNC_TEST_TODAY=2020-01-01 ss A now; }
check "удаление «в прошлом»" past
check "старая копия в корзине есть" has A 's7.jsonl' trash
run A now >/dev/null   # новый день — очистка корзины
check "копия старше TRASH_DAYS удалена" not has A 's7.jsonl' trash
check "свежая копия осталась" has A 's4.jsonl' trash

echo "== Массовое удаление: синхронизация ждёт решения пользователя"
mkdir -p "$T/s3/bucket2"
for m in F G; do mac $m; setconf $m bucket2; done
for i in 1 2 3 4; do say F -tmp-p2 "d$i" "сессия $i"; done
run F now >/dev/null; run G now >/dev/null
delmany() { rm "$T/F/projects/-tmp-p2/d1.jsonl" "$T/F/projects/-tmp-p2/d2.jsonl" "$T/F/projects/-tmp-p2/d3.jsonl"; }
delmany
check "удалено больше половины: синхронизация остановлена" not run F now
check "в ошибке — подсказка sessync deletes" contains "$(stf F error)" "sessync deletes"
check "deletes показывает, что удалено" has F 'd1.jsonl' deletes
check "deletes --undo" run F deletes --undo
check "удалённое вернулось из хранилища" test -f "$T/F/projects/-tmp-p2/d1.jsonl"
check "ошибки больше нет" test ! -e "$(stf F error)"
delmany
run F now >/dev/null
check "deletes --apply" run F deletes --apply
check "удалённое — в корзине" has F 'd3.jsonl' trash
check "другой Mac тоже спрашивает" not run G now
check "и называет, где удалили" has G 'на другом Mac' deletes
check "другой Mac: deletes --apply" run G deletes --apply
check "на другом Mac удалено" test ! -e "$T/G/projects/-tmp-p2/d1.jsonl" -a -f "$T/G/projects/-tmp-p2/d4.jsonl"
check "deletes без остановки: подтверждать нечего" has G 'нечего' deletes

echo "== Отправляется и получается только дописанное"
mkdir -p "$T/s3/bucket4"
for m in P Q R; do mac $m; setconf $m bucket4; done
segs() { at "$1" "rclone lsf -R --files-only --format sp ss:seg/${2:-projects}" | sort; }
nsegs() { segs "$@" | grep -c .; }
same() { cmp -s "$T/$1/projects/$3" "$T/$2/projects/$3"; }
uplog() { grep 'готово' "$(stf "$1" sync.log)" | tail -1; }
L=-tmp-p4/long.jsonl
pad=$(printf '%0300d' 0)
for i in $(seq 1 200); do say P -tmp-p4 long "строка $i $pad"; done
run P now >/dev/null; run Q now >/dev/null
check "Q получил сессию байт в байт" same P Q $L
check "в хранилище пока только основа, без хвостов" test "$(nsegs P)" = 0
ino=$(stat -f %i "$T/Q/projects/$L")
say P -tmp-p4 long "дописано на P"
run P now >/dev/null
check "дописанное ушло одним хвостом" test "$(nsegs P)" = 1
check "в хвосте — только дописанная строка" test "$(segs P | cut -d';' -f1)" = "$(tail -n1 "$T/P/projects/$L" | wc -c | tr -d ' ')"
check "в журнале — килобайты, а не вся сессия" sh -c "printf '%s' \"\$1\" | grep -q 'отправлено 1 (1 КБ), получено 0 (0 КБ)'" _ "$(uplog P)"
run Q now >/dev/null
check "Q дописал хвост к своему файлу" same P Q $L
check "Q: тот же файл, а не замена целиком" test "$(stat -f %i "$T/Q/projects/$L")" = "$ino"
check "без изменений: ничего не передаётся" has Q 'отправлено файлов 0, получено 0' now

for i in 1 2 3; do say P -tmp-p4 long "ещё $i"; run P now >/dev/null; done
check "хвостов уровня 0 — четыре" test "$(segs P | grep -c -- '-0-')" = 4
run P now >/dev/null
check "не затихла — не сворачивается" test "$(nsegs P)" = 4
export SESSYNC_QUIET=0
run Q now >/dev/null
check "свёртку делает только Mac, дописавший последним" test "$(nsegs Q)" = 4
run P now >/dev/null
check "затихшая сессия свёрнута в один хвост уровня 1" sh -c "test \"\$(printf '%s\n' \"\$1\" | grep -c .)\" = 1 && printf '%s' \"\$1\" | grep -q -- '-1-'" _ "$(segs P)"
unset SESSYNC_QUIET
run Q now >/dev/null
check "после свёртки у Q тот же файл" same P Q $L
export SESSYNC_MAX_L0=3
for i in 1 2 3; do say P -tmp-p4 long "активно $i"; run P now >/dev/null; done
unset SESSYNC_MAX_L0
check "много хвостов в активной сессии — сворачиваются сразу" test "$(segs P | grep -c -- '-0-')" = 0 -a "$(nsegs P)" = 2
run R now >/dev/null
check "новый Mac собрал сессию из основы и хвостов" same P R $L
run Q now >/dev/null
check "и Q получил то же" same P Q $L
size0=$(at P "rclone lsf --format s ss:projects/$L")
# чужой хвост вне цепочки (остаток гонки двух Mac): на файл не влияет, под новой основой убирается
at P "printf x | rclone rcat ss:seg/projects/$L/0000000000000001-0000000000000002-0-000000000000-hostZ 2>/dev/null"
run Q now >/dev/null
check "хвост вне цепочки на файл не влияет" same P Q $L
for i in $(seq 1 220); do say P -tmp-p4 long "много нового $i $pad"; done
run P now >/dev/null
check "хвосты догнали основу — новая основа целиком" test "$(at P "rclone lsf --format s ss:projects/$L")" -gt "$size0"
check "под новой основой убраны все хвосты, и вне цепочки тоже" test "$(nsegs P)" = 0
run Q now >/dev/null; run R now >/dev/null
check "после новой основы у всех тот же файл" sh -c "cmp -s '$T/P/projects/$L' '$T/Q/projects/$L' && cmp -s '$T/P/projects/$L' '$T/R/projects/$L'"

echo "== Недописанная строка, конфликт, открытая сессия, потерянное состояние"
printf '{"type":"user","message":{"role":"user","content":"полстроки' >> "$T/P/projects/$L"
run P now >/dev/null
check "недописанная строка не отправляется" test "$(nsegs P)" = 0
printf ' и конец"},"timestamp":"2026-10-10T11:00:00Z"}\n' >> "$T/P/projects/$L"
run P now >/dev/null; run Q now >/dev/null
check "дописанная до конца — отправляется" same P Q $L
say Q -tmp-p4 long "коротко с Q"
say P -tmp-p4 long "с P длиннее, чем с Q, — эта версия останется основной"
run Q now >/dev/null; run P now >/dev/null; run Q now >/dev/null; run R now >/dev/null
check "конфликт: у всех под основным именем более длинная версия" sh -c "cmp -s '$T/P/projects/$L' '$T/Q/projects/$L' && cmp -s '$T/P/projects/$L' '$T/R/projects/$L'"
check "конфликт: в основной — строка P" contains "$T/Q/projects/$L" "с P длиннее"
check "конфликт: версия Q сохранена копией" contains "$T/Q/projects/$L.conflict1" "коротко с Q"
check "конфликт: копия есть и на P" contains "$T/P/projects/$L.conflict1" "коротко с Q"
check "конфликт: одна копия, не две" test ! -e "$T/Q/projects/$L.conflict2" -a ! -e "$T/P/projects/$L.conflict2"
run P now >/dev/null; run Q now >/dev/null; run P now >/dev/null
check "conflicts --delete на одном Mac" run P conflicts --delete
run P now >/dev/null; run Q now >/dev/null
check "копия конфликта удалена и на другом Mac" test ! -e "$T/Q/projects/$L.conflict1"
say P -tmp-p4 gone "сессия, которую удалят"
run P now >/dev/null; run Q now >/dev/null
mkdir -p "$T/Q/sessions"
printf '{"pid":%s,"sessionId":"gone"}\n' $$ > "$T/Q/sessions/$$.json"
rm "$T/P/projects/-tmp-p4/gone.jsonl"
run P now >/dev/null; run Q now >/dev/null
check "удалена на другом Mac, но открыта здесь — не удаляется" test -f "$T/Q/projects/-tmp-p4/gone.jsonl"
rm "$T/Q/sessions/$$.json"
run Q now >/dev/null
check "закрыли — удаляется" test ! -e "$T/Q/projects/-tmp-p4/gone.jsonl"
rm "$(stf Q engine/projects.json)"
check "состояние потеряно: без конфликтов и повторной отправки" has Q 'отправлено файлов 0, получено 0' now
check "состояние потеряно: копий конфликта нет" test -z "$(find "$T/Q/projects" -name '*.conflict*')"
run Q now >/dev/null
check "сверенное заново дальше сверяется по размеру и времени" python3 -I -c '
import json, sys
f = json.load(open(sys.argv[1]))["files"]
sys.exit(any(v.get("size") == -1 for v in f.values() if "s" in v))' "$(stf Q engine/projects.json)"

echo "== Вложения сессий: целиком"
A1=-tmp-p4/long/tool-results/t1.txt
mkdir -p "$T/P/projects/-tmp-p4/long/tool-results"
echo "вложение" > "$T/P/projects/$A1"
for i in 2 3 4 5; do echo "вложение $i" > "$T/P/projects/-tmp-p4/long/tool-results/t$i.txt"; done
run P now >/dev/null; run Q now >/dev/null
check "вложение пришло" same P Q $A1
echo "вложение, изменённое на P" > "$T/P/projects/$A1"
run P now >/dev/null; run Q now >/dev/null
check "изменённое вложение пришло" contains "$T/Q/projects/$A1" "изменённое на P"
A2=-tmp-p4/long/tool-results/t2.txt
echo "одинаково на обоих" > "$T/P/projects/$A2"; echo "одинаково на обоих" > "$T/Q/projects/$A2"
run P now >/dev/null; run Q now >/dev/null; run P now >/dev/null
check "одинаково изменённое на обоих Mac — не конфликт" test ! -e "$T/Q/projects/$A2.conflict1" -a ! -e "$T/P/projects/$A2.conflict1"
check "и дальше спокойно" has Q 'отправлено файлов 0, получено 0' now
echo old > "$T/P/projects/-tmp-p4/old.sessync.tmp"; touch -t 202601010000 "$T/P/projects/-tmp-p4/old.sessync.tmp"
echo new > "$T/P/projects/-tmp-p4/new.sessync.tmp"
run P now >/dev/null; run Q now >/dev/null
check "старый временный файл прерванного запуска убран" test ! -e "$T/P/projects/-tmp-p4/old.sessync.tmp"
check "свежий не тронут (его может писать restore)" test -e "$T/P/projects/-tmp-p4/new.sessync.tmp"
check "временные файлы не синхронизируются" test ! -e "$T/Q/projects/-tmp-p4/new.sessync.tmp"
rm "$T/P/projects/-tmp-p4/new.sessync.tmp"
echo "версия Q, она больше версии P" > "$T/Q/projects/$A1"
echo "версия P" > "$T/P/projects/$A1"
run Q now >/dev/null; run P now >/dev/null; run P now >/dev/null; run Q now >/dev/null
check "конфликт вложения: у обоих большая версия" sh -c "grep -q 'версия Q' '$T/P/projects/$A1' && grep -q 'версия Q' '$T/Q/projects/$A1'"
check "конфликт вложения: меньшая — копией у обоих" sh -c "grep -q 'версия P' '$T/P/projects/$A1.conflict1' && grep -q 'версия P' '$T/Q/projects/$A1.conflict1'"
rm "$T/P/projects/$A1" "$T/P/projects/$A1.conflict1"
run P now >/dev/null; run Q now >/dev/null
check "удалённое вложение удалено и на другом Mac" test ! -e "$T/Q/projects/$A1" -a ! -e "$T/Q/projects/$A1.conflict1"
check "и лежит в корзине" has P 't1.txt' trash
printf 'обрезано\n' > "$T/Q/projects/$L"   # транскрипт стал короче — порча, а не правка
run Q now >/dev/null; run P now >/dev/null
check "обрезанный транскрипт не затирает полный" test "$(lines "$T/P/projects/$L")" -gt 100
check "обрезанная версия сохранена копией" contains "$T/Q/projects/$L.conflict1" "обрезано"
check "на Q снова полная версия" same P Q $L
run Q conflicts --delete >/dev/null; run Q now >/dev/null; run P now >/dev/null

echo "== Корзина и возврат сессии с хвостами"
say P -tmp-p4 segd "основа"
run P now >/dev/null
for i in $(seq 1 30); do say P -tmp-p4 segd "основа $i $pad"; done
run P now >/dev/null
say P -tmp-p4 segd "хвост 1"; run P now >/dev/null
say P -tmp-p4 segd "хвост 2"; run P now >/dev/null
check "у сессии есть хвосты" test "$(segs P | grep -c segd)" -ge 2
cp "$T/P/projects/-tmp-p4/segd.jsonl" "$T/segd.saved"
rm "$T/P/projects/-tmp-p4/segd.jsonl"
run P now >/dev/null
check "удалённая сессия с хвостами — в корзине" has P 'segd.jsonl' trash
check "хвосты удалённой сессии убраны из хранилища" test "$(segs P | grep -c segd)" = 0
check "restore собирает сессию из основы и хвостов" run P restore segd.jsonl
check "собрана байт в байт" cmp -s "$T/segd.saved" "$T/P/projects/-tmp-p4/segd.jsonl"
run P now >/dev/null; run Q now >/dev/null
check "возвращённая сессия ушла на другой Mac" cmp -s "$T/segd.saved" "$T/Q/projects/-tmp-p4/segd.jsonl"
check "status --remote показывает хвосты" has P 'хвосты' status --remote

echo "== История промптов: свой файл только дописывается"
for i in $(seq 1 40); do echo "{\"display\":\"промпт P $i $pad\",\"timestamp\":$i}" >> "$T/P/history.jsonl"; done
run P now >/dev/null; run Q now >/dev/null
check "Q получил историю P" contains "$T/Q/history.jsonl" "промпт P 40"
echo '{"display":"новый промпт P","timestamp":100}' >> "$T/P/history.jsonl"
run P now >/dev/null
check "ушёл только новый промпт" test "$(segs P history | grep hostP | cut -d';' -f1)" = "$(tail -n1 "$T/P/history.jsonl" | wc -c | tr -d ' ')"
run Q now >/dev/null
check "Q получил новый промпт" contains "$T/Q/history.jsonl" "новый промпт P"
echo '{"display":"промпт Q","timestamp":101}' >> "$T/Q/history.jsonl"
run Q now >/dev/null; run P now >/dev/null
check "P получил промпт Q" contains "$T/P/history.jsonl" "промпт Q"
check "свой промпт не задвоился" test "$(grep -c 'новый промпт P' "$T/P/history.jsonl")" = 1
mv "$(stf P engine/history.json)" "$T/history-state.saved"
mkdir -p "$T/P/state/sessync/history.old"; mv "$T"/P/state/sessync/history/* "$T/P/state/sessync/history.old/"
run P now >/dev/null
check "переустановка: свой файл истории продолжается, без конфликта" test -z "$(find "$T/P/state/sessync/history" -name '*.conflict*')"
check "переустановка: промпты не задвоились" test "$(grep -c 'новый промпт P' "$T/P/history.jsonl")" = 1

echo "== Другое имя пользователя на другом Mac"
mkdir -p "$T/s3/bucket7"
for m in U V; do mac $m; setconf $m bucket7; done
hu() { HOME=/Users/alice ss U "$@"; }   # первый Mac: /Users/alice
hv() { HOME=/home/bob ss V "$@"; }      # второй: другое имя и другая система путей
mkdir -p "$T/U/projects/-Users-alice-work-app"
printf '{"type":"user","message":{"role":"user","content":"путь alice"},"cwd":"/Users/alice/work/app","timestamp":"2026-10-10T10:00:00Z","sessionId":"u1"}\n' \
  > "$T/U/projects/-Users-alice-work-app/u1.jsonl"
echo '{"display":"промпт alice","timestamp":1,"project":"/Users/alice/work/app"}' > "$T/U/history.jsonl"
check "U: синхронизация" hu now
check "V: синхронизация" hv now
check "V: папка проекта названа по своей домашней папке" test -f "$T/V/projects/-home-bob-work-app/u1.jsonl"
check "V: под чужим именем папки нет" test ! -e "$T/V/projects/-Users-alice-work-app"
check "V: в истории промптов — свой путь проекта" contains "$T/V/history.jsonl" '"project":"/home/bob/work/app"'
printf '{"type":"user","message":{"role":"user","content":"ответ bob"},"cwd":"/home/bob/work/app","timestamp":"2026-10-10T11:00:00Z","sessionId":"u1"}\n' \
  >> "$T/V/projects/-home-bob-work-app/u1.jsonl"
mkdir -p "$T/V/projects/-home-bob-other"; say V -home-bob-other v1 "проект bob"
echo '{"display":"промпт bob","timestamp":2,"project":"/home/bob/other"}' >> "$T/V/history.jsonl"
check "V: отправка" hv now
check "U: получение" hu now
check "U: дописанное пришло в ту же сессию" contains "$T/U/projects/-Users-alice-work-app/u1.jsonl" "ответ bob"
check "U: новый проект V — под домашней папкой U" test -f "$T/U/projects/-Users-alice-other/v1.jsonl"
check "U: промпт V — с путём U" contains "$T/U/history.jsonl" '"project":"/Users/alice/other"'
check "в хранилище — имена по домашней папке хранилища" sh -c "$(declare -f at); T='$T' here='$here'; at U 'rclone lsf ss:projects' | grep -q '^-Users-alice-other/'"
check "поиск на V: путь проекта — свой" sh -c "$(declare -f ss); T='$T' here='$here'; HOME=/home/bob ss V find путь | grep -q '~/work/app'"
check "status на V называет пересчёт папок" sh -c "$(declare -f ss); T='$T' here='$here'; HOME=/home/bob ss V status | grep -q '/Users/alice в хранилище = /home/bob'"

echo "== Хранилище rclone: любое, что понимает rclone"
for m in W X; do mac $m; printf 'STORAGE=rclone\nREMOTE=%s\n' "$T/rclone-remote/sessync" > "$T/$m/config/sessync/config"; done
mkdir -p "$T/rclone-remote"
say W -tmp-rc r1 "через rclone"
check "W: синхронизация через rclone" run W now
run X now >/dev/null
check "X: получил сессию" contains "$T/X/projects/-tmp-rc/r1.jsonl" "через rclone"
check "в хранилище rclone — шифротекст" absent "$T/rclone-remote" "через rclone"
check "status называет хранилище rclone" has X 'rclone' status

echo "== English"
en() { SESSYNC_LANG=en ss "$@"; }
check "английский: итог синхронизации" sh -c "$(declare -f ss en); T='$T' here='$here'; en A now | grep -q 'Done in'"
check "английский: status" sh -c "$(declare -f ss en); T='$T' here='$here'; en A status | grep -q 'Automatic sync: on'"
check "английский: поиск" sh -c "$(declare -f ss en); T='$T' here='$here'; en A find нетакогослова | grep -q 'Nothing found'"
check "английский: справка" sh -c "$(declare -f ss en); T='$T' here='$here'; en A help | grep -q 'sync now'"
check "английский: журнал движка" sh -c "$(declare -f ss en); T='$T' here='$here'; say() { :; }; printf '{\"type\":\"user\"}\n' >> '$T/A/projects/-tmp-p1/s1.jsonl'; en A now >/dev/null; grep -q 'appended' '$(stf A sync.log)'"

echo "== Повтор, если синхронизацию запросили, пока она шла"
mkdir "$(stf A lock)"
check "занято: выходит сразу и без ошибки" has A 'пройдёт ещё раз' now
check "занято: просьба повторить записана" test -f "$(stf A again)"
rmdir "$(stf A lock)"
check "следующая синхронизация проходит" run A now
check "и снимает просьбу" test ! -e "$(stf A again)"
check "блокировка снята" test ! -e "$(stf A lock)"

echo "== Мелочи"
src() { CLAUDE_CONFIG_DIR="$T/A" XDG_CONFIG_HOME="$T/A/config" XDG_STATE_HOME="$T/A/state" bash -c "source '$here/bin/sessync' version >/dev/null; $1"; }
hostid_ok() { env -u SESSYNC_HOST bash -c "source '$here/bin/sessync' version >/dev/null; host_id" | grep -Eq -- '-[0-9A-F]{8}$'; }
check "файл истории Mac: имя + начало аппаратного UUID (имена Mac совпадают)" hostid_ok
mkdir -p "$T/dotfiles" "$T/H/projects"; setconf H bucket
printf '{"cleanupPeriodDays": 30}\n' > "$T/dotfiles/settings.json"; chmod 644 "$T/dotfiles/settings.json"
ln -s "$T/dotfiles/settings.json" "$T/H/settings.json"
run H now >/dev/null
check "срок хранения: settings.json-ссылка осталась ссылкой" test -L "$T/H/settings.json"
check "срок хранения: записан в файл по ссылке, права прежние" sh -c "jq -e '.cleanupPeriodDays == 36500' '$T/dotfiles/settings.json' && test \"\$(stat -f %Lp '$T/dotfiles/settings.json')\" = 644"
pb="sessync-test-$$"
pbread() { osascript -l JavaScript -e "ObjC.import('AppKit'); var pb = \$.NSPasteboard.pasteboardWithName('$pb'); JSON.stringify([ObjC.deepUnwrap(pb.types), ObjC.unwrap(pb.stringForType('public.utf8-plain-text'))])"; }
printf 'секрет "в кавычках"' | SESSYNC_TEST_PASTEBOARD="$pb" src clip
out=$(pbread)
marked() { grep -q ConcealedType <<<"$out" && grep -q TransientType <<<"$out"; }
check "export: значение в буфере как есть" grep -qF 'секрет \"в кавычках\"' <<<"$out"
check "export: пометки «скрытое» и «временное» для истории буфера" marked
printf '' | SESSYNC_TEST_PASTEBOARD="$pb" src clip
out=$(pbread)
check "export: пустой ввод очищает буфер" sh -c "! grep -q секрет" <<<"$out"
osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSPasteboard.pasteboardWithName('$pb').releaseGlobally" >/dev/null 2>&1

echo "== sessync setup: хранилище, ключи и пароль — в терминале, как у человека"
PYT=${SESSYNC_PYTHON:-python3}
sm() {  # sm M command… — sessync on "Mac" M: secrets in its folder instead of the Keychain
  local m=$1; shift
  env -u SESSYNC_TEST_S3_ACCESS_KEY -u SESSYNC_TEST_S3_SECRET_KEY -u SESSYNC_TEST_PASSPHRASE \
    SESSYNC_TEST_KEYCHAIN="$T/$m/keychain" SESSYNC_BIN="$here/bin/sessync" \
    CLAUDE_CONFIG_DIR="$T/$m" XDG_CONFIG_HOME="$T/$m/config" XDG_STATE_HOME="$T/$m/state" \
    XDG_CACHE_HOME="$T/$m/cache" SESSYNC_HOST="host$m" "$here/bin/sessync" "$@"
}
tsm() {  # tsm M "command" action… — the same in a terminal (tests/tty.py); what it printed — in $T/M.out
  local m=$1 a=$2; shift 2
  "$PYT" -I "$here/tests/tty.py" "$@" -- bash -c "$(declare -f sm); T='$T' here='$here'; sm $m $a" > "$T/$m.out" 2>&1
}
smhas() { local m=$1 pat=$2; shift 2; sm "$m" "$@" 2>&1 | grep -q -- "$pat"; }
conf() { grep -qx -- "$2" "$T/$1/config/sessync/config"; }       # conf M LINE — a line of M's config
kc() { cat "$T/$1/keychain/$2" 2>/dev/null; }                     # kc M name — M's saved secret
shown() { grep -qF -- "$2" "$T/$1.out"; }                         # shown M text — it was on screen

check "без терминала: отказ" not sm M1 setup </dev/null
check "без терминала: просит свой терминал" smhas M1 'в своём терминале' setup </dev/null
mkdir -p "$T/s3/b-r2" "$T/M1/projects"   # бакет пользователь создаёт сам
check "первый Mac: Cloudflare R2, новый пароль, hook'и" tsm M1 setup \
  --expect 'Выбор [1-5]:' --send 1 --expect 'ID аккаунта Cloudflare' --send acc123 \
  --expect 'Имя бакета:' --send b-r2 \
  --expect 'S3 Access Key:' --secret AKR2TEST --expect 'S3 Secret Key:' --secret SKR2TEST-secret \
  --expect 'Enter — создать новый' --secret '' --expect '[Y/n]' --send '' --expect 'Первая синхронизация'
check "R2: адрес по ID аккаунта" conf M1 'ENDPOINT=https://acc123.r2.cloudflarestorage.com'
check "R2: провайдер, регион, бакет, язык" sh -c "$(declare -f conf); T='$T'; conf M1 PROVIDER=Cloudflare && conf M1 REGION=auto && conf M1 BUCKET=b-r2 && conf M1 STORAGE=s3 && conf M1 LANGUAGE=ru"
check "R2: подсказка, где взять ключи" shown M1 'Manage API tokens'
check "ключи сохранены" test "$(kc M1 s3-access-key)" = AKR2TEST -a "$(kc M1 s3-secret-key)" = SKR2TEST-secret
check "создан пароль: 32 буквы и цифры" grep -Eqx '[A-Za-z0-9]{32}' "$T/M1/keychain/passphrase"
check "ключи и пароль не попали на экран" sh -c "! grep -qF -e AKR2TEST -e SKR2TEST -e '$(kc M1 passphrase)' '$T/M1.out'"
check "проверка доступа и пароля прошла" shown M1 'Готово: доступ к хранилищу есть'
check "hook'и добавлены" jq -e '[.hooks.SessionStart[].hooks[].command] | any(test("sessync hook start"))' "$T/M1/settings.json"
say M1 -tmp-st st1 "сессия после setup"
check "после setup синхронизация работает" sm M1 now

mkdir -p "$T/M2/projects"; printf '{"cleanupPeriodDays": 36500}\n' > "$T/M2/settings.json"
check "второй Mac с другим паролем: проверка не проходит" not tsm M2 setup \
  --expect 'Выбор [1-5]:' --send 1 --expect 'ID аккаунта' --send acc123 --expect 'Имя бакета:' --send b-r2 \
  --expect 'S3 Access Key:' --secret AKR2TEST --expect 'S3 Secret Key:' --secret SKR2TEST-secret \
  --expect 'Enter — создать новый' --secret wrong-password-12345 --expect 'Проверка не прошла'
check "второй Mac: причина — пароль не тот" shown M2 'пароль шифрования не тот'
check "второй Mac: повторный setup — без выбора хранилища, ключи остаются, пароль заменяется" tsm M2 setup \
  --expect 'S3 Access Key уже есть' --secret '' --expect 'S3 Secret Key уже есть' --secret '' \
  --expect 'Пароль шифрования уже есть' --secret "$(kc M1 passphrase)" --expect 'Готово:' \
  --expect '[Y/n]' --send n --expect 'Первая синхронизация'
check "второй Mac: меню хранилища не показывалось" not shown M2 'Выбор [1-5]'
check "второй Mac: ключи прежние" test "$(kc M2 s3-access-key)" = AKR2TEST
check "второй Mac: от hook'ов отказались — их нет" not jq -e '.hooks' "$T/M2/settings.json"
check "второй Mac: сессии первого пришли" sh -c "$(declare -f sm); T='$T' here='$here'; sm M2 now && test -f '$T/M2/projects/-tmp-st/st1.jsonl'"
check "setup --storage, неверный выбор: хранилище не изменено" not tsm M1 'setup --storage' \
  --expect 'Выбор [1-5]:' --send 9 --expect 'не изменено'
check "и настройки прежние" conf M1 BUCKET=b-r2

mkdir -p "$T/s3/b-b2" "$T/M3/projects"
check "короткий пароль: отказ" not tsm M3 setup \
  --expect 'Выбор [1-5]:' --send 2 --expect 'Регион B2' --send us-west-004 --expect 'Имя бакета:' --send b-b2 \
  --expect 'S3 Access Key:' --secret K --expect 'S3 Secret Key:' --secret S \
  --expect 'Enter — создать новый' --secret short --expect 'Слишком короткий'
check "короткий пароль не сохранён" test ! -e "$T/M3/keychain/passphrase"
check "B2: адрес по региону" conf M3 'ENDPOINT=https://s3.us-west-004.backblazeb2.com'
check "B2: регион" conf M3 REGION=us-west-004
check "B2: подсказка про Application Keys" shown M3 'Application Keys'

mkdir -p "$T/s3/b-aws" "$T/M4/projects"
check "Amazon S3" tsm M4 setup \
  --expect 'Выбор [1-5]:' --send 3 --expect 'Регион AWS' --send eu-central-1 --expect 'Имя бакета:' --send b-aws \
  --expect 'S3 Access Key:' --secret AKAWS --expect 'S3 Secret Key:' --secret SKAWS \
  --expect 'Enter — создать новый' --secret aws-password-123456 --expect '[Y/n]' --send n --expect 'Первая синхронизация'
check "AWS: без адреса, с регионом" sh -c "$(declare -f conf); T='$T'; conf M4 ENDPOINT= && conf M4 REGION=eu-central-1 && conf M4 PROVIDER=AWS"
check "AWS: подсказка про IAM" shown M4 IAM
check "AWS: status называет регион" smhas M4 'b-aws (AWS eu-central-1)' status

mkdir -p "$T/s3/b-other" "$T/M5/config/sessync"
printf 'TRASH_DAYS=7\nINTERVAL=300\n' > "$T/M5/config/sessync/config"
check "другое S3-хранилище, регион пустой" tsm M5 setup \
  --expect 'Выбор [1-5]:' --send 4 --expect 'Адрес (endpoint' --send https://s3.example.net \
  --expect 'Регион (Enter' --send '' --expect 'Имя бакета:' --send b-other \
  --expect 'S3 Access Key:' --secret AKO --expect 'S3 Secret Key:' --secret SKO \
  --expect 'Enter — создать новый' --secret '' --expect '[Y/n]' --send n --expect 'Первая синхронизация'
check "другое S3: адрес и пустой регион" sh -c "$(declare -f conf); T='$T'; conf M5 ENDPOINT=https://s3.example.net && conf M5 REGION= && conf M5 PROVIDER=Other"
check "другое S3: подсказка про ключ только к бакету" shown M5 'не ключ всего аккаунта'
check "прочие строки настроек остались" sh -c "$(declare -f conf); T='$T'; conf M5 TRASH_DAYS=7 && conf M5 INTERVAL=300"

mkdir -p "$T/M6/projects"
check "rclone: без двоеточия — отказ" not tsm M6 setup \
  --expect 'Выбор [1-5]:' --send 5 --expect 'Хранилище и папка' --send gdrive --expect 'не изменено'
check "rclone: хранилище с папкой" tsm M6 setup \
  --expect 'Выбор [1-5]:' --send 5 --expect 'Хранилище и папка' --send ":local:$T/rc-setup/sessync" \
  --expect 'Enter — создать новый' --secret '' --expect '[Y/n]' --send n --expect 'Первая синхронизация'
check "rclone: настройки" sh -c "$(declare -f conf); T='$T'; conf M6 STORAGE=rclone && conf M6 'REMOTE=:local:$T/rc-setup/sessync' && conf M6 BUCKET="
check "rclone: ключи S3 не спрашивались" not shown M6 'S3 Access Key'
check "rclone: папка создана, контрольный файл записан" test -d "$T/rc-setup/sessync/v1-check"
say M6 -tmp-st r1 "через rclone после setup"
check "rclone: синхронизация работает" sm M6 now

echo "== sessync export: ключи и пароль по одному через буфер обмена (тестовый, не общий)"
pbx="sessync-test-export-$$"
cat > "$T/pbget" <<'EOF'
#!/bin/sh
exec osascript -l JavaScript -e 'function run(a) { ObjC.import("AppKit"); return ObjC.unwrap($.NSPasteboard.pasteboardWithName(a[0]).stringForType("public.utf8-plain-text")) || "" }' "$1"
EOF
chmod +x "$T/pbget"
check "без терминала: отказ" not sm M1 export </dev/null
mkdir -p "$T/M7"
check "не настроено: отказ с подсказкой" not tsm M7 export --expect 'сначала sessync setup'
export SESSYNC_TEST_PASTEBOARD=$pbx
check "R2: четыре шага" tsm M1 export \
  --expect 'Шаг 1 из 4' --expect 'нажмите Enter.' --send '' \
  --expect 'Шаг 2 из 4' --expect 'нажмите Enter.' --run "'$T/pbget' $pbx > '$T/clip2'" --send '' \
  --expect 'Шаг 3 из 4' --expect 'нажмите Enter.' --run "'$T/pbget' $pbx > '$T/clip3'" --send '' \
  --expect 'Шаг 4 из 4' --expect 'очистится.' --run "'$T/pbget' $pbx > '$T/clip4'" --send '' \
  --expect 'буфер обмена очищен'
check "шаг 1: адрес хранилища для «Паролей»" shown M1 'Веб-сайт» напишите адрес хранилища: acc123.r2.cloudflarestorage.com'
check "шаг 2: в буфере — Access Key" test "$(cat "$T/clip2")" = AKR2TEST
check "шаг 3: в буфере — пароль шифрования" test "$(cat "$T/clip3")" = "$(kc M1 passphrase)"
check "шаг 4: Secret Key и настройки для заметок" sh -c "grep -qx 'S3 Secret Key: SKR2TEST-secret' '$T/clip4' && grep -qx 'BUCKET=b-r2' '$T/clip4' && grep -qx 'ENDPOINT=https://acc123.r2.cloudflarestorage.com' '$T/clip4'"
check "в конце буфер пуст" test -z "$("$T/pbget" "$pbx")"
check "на экран ничего секретного" sh -c "! grep -qF -e AKR2TEST -e SKR2TEST -e '$(kc M1 passphrase)' '$T/M1.out'"
check "rclone: без ключей S3" tsm M6 export \
  --expect 'Шаг 1 из 4' --send '' --expect 'Впишите sessync' --send '' \
  --expect 'Шаг 3 из 4' --expect 'нажмите Enter.' --run "'$T/pbget' $pbx > '$T/clip3'" --send '' \
  --expect 'Шаг 4 из 4' --expect 'очистится.' --run "'$T/pbget' $pbx > '$T/clip4'" --send '' \
  --expect 'буфер обмена очищен'
check "rclone: адрес для «Паролей» — rclone.org" shown M6 'адрес хранилища: rclone.org'
check "rclone: шаг 3 — пароль" test "$(cat "$T/clip3")" = "$(kc M6 passphrase)"
check "rclone: шаг 4 — настройки, без Secret Key" sh -c "grep -qx 'REMOTE=:local:$T/rc-setup/sessync' '$T/clip4' && ! grep -q 'Secret Key' '$T/clip4'"
check "AWS: адрес для «Паролей» — s3.amazonaws.com" tsm M4 export \
  --expect 'адрес хранилища: s3.amazonaws.com' --send '' --expect 'Шаг 2 из 4' --send '' \
  --expect 'Шаг 3 из 4' --send '' --expect 'Шаг 4 из 4' --send '' --expect 'буфер обмена очищен'
unset SESSYNC_TEST_PASTEBOARD
osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSPasteboard.pasteboardWithName('$pbx').releaseGlobally" >/dev/null 2>&1

echo "== Поиск"
check "find находит по переписке" sh -c "$(declare -f ss); T='$T' here='$here'; ss B find уникальнаяфраза | grep -q 'claude -r s5'"
check "find: несуществующее не находит" has B 'Ничего не найдено' find нетакогослова
# В транскрипт может попасть вывод команд или текст страницы с ESC-последовательностями
say A -tmp-p1 s6 'опасныйтекст \u001b]0;pwned\u0007 \u001b[31mкрасный‮ конец'
out=$(ss A find опасныйтекст)
check "find находит сессию с управляющими символами" grep -q 'claude -r s6' <<<"$out"
check "find не выводит ESC, BEL и bidi" sh -c "! printf '%s' \"\$1\" | LC_ALL=C grep -q \$'[\\x1b\\x07]\\|\\xe2\\x80\\xae'" _ "$out"

echo "== Права файлов: только владелец, как у транскриптов Claude Code"
perm() { stat -f %Lp "$1"; }
check "индекс поиска — 700" test "$(perm "$T/A/cache/sessync/find")" = 700
check "файлы индекса — 600" test "$(perm "$(find "$T/A/cache/sessync/find/text" -type f | head -1)")" = 600
check "состояние sessync — 700" test "$(perm "$T/B/state/sessync")" = 700
check "чужая история промптов — 600" test "$(perm "$(find "$T/B/state/sessync/history" -type f | head -1)")" = 600
check "скачанные сессии — 600" test "$(perm "$T/B/projects/-tmp-p1/s4.jsonl")" = 600

echo "== install.sh и uninstall.sh"
H="$T/home"; mkdir -p "$H/.claude" "$H/.local/bin"
cat > "$H/.claude/settings.json" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "echo чужой hook"}]},
                     {"matcher": "startup|resume", "hooks": [{"type": "command", "command": "[ -x ~/.local/bin/cc-sync ] && ~/.local/bin/cc-sync hook start || true"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "echo stop"}]}]
  }
}
JSON
ln -s "$here/bin/cc-sync" "$H/.local/bin/cc-sync"; ln -s "$here/bin/cc-find" "$H/.local/bin/cc-find"   # версия до 2.0
inst() { HOME="$H" CLAUDE_CONFIG_DIR="$H/.claude" SESSYNC_SKIP_BREW=1 "$here/$1"; }
check "install.sh" inst install.sh
s="$H/.claude/settings.json"
check "hook старта добавлен" jq -e '[.hooks.SessionStart[].hooks[].command] | any(test("sessync hook start"))' "$s"
check "hook конца добавлен" jq -e '[.hooks.SessionEnd[].hooks[].command] | any(test("sessync hook end"))' "$s"
check "старый hook cc-sync убран" jq -e '[.hooks[][].hooks[].command] | all(test("cc-sync") | not)' "$s"
check "чужие hook'и на месте" jq -e '([.hooks.SessionStart[].hooks[].command] | index("echo чужой hook")) and .hooks.Stop' "$s"
check "срок хранения поднят" jq -e '.cleanupPeriodDays == 36500' "$s"
check "команда в ~/.local/bin" test -L "$H/.local/bin/sessync"
check "старые команды cc-sync и cc-find убраны" test ! -L "$H/.local/bin/cc-sync" -a ! -L "$H/.local/bin/cc-find"
check "повторный install.sh ничего не меняет" sh -c "HOME='$H' CLAUDE_CONFIG_DIR='$H/.claude' SESSYNC_SKIP_BREW=1 '$here/install.sh' | grep -q 'уже на месте'"
check "uninstall.sh" inst uninstall.sh
check "hook'и sessync убраны" jq -e '[.hooks[]?[]?.hooks[]?.command] | all(test("sessync") | not)' "$s"
check "чужие hook'и остались" jq -e '([.hooks.SessionStart[].hooks[].command] | index("echo чужой hook")) and .hooks.Stop' "$s"
check "команда убрана" test ! -e "$H/.local/bin/sessync"
echo '{"hooks": {"SessionStart": [{"matcher": "без hooks"}]}}' > "$T/dotfiles/s2.json"
rm "$s"; ln -s "$T/dotfiles/s2.json" "$s"
check "install.sh: запись hook'а без поля hooks не ломает jq" inst install.sh
check "install.sh: settings.json-ссылка осталась ссылкой" test -L "$s"
check "install.sh: hook записан в файл по ссылке" jq -e '[.hooks.SessionStart[].hooks[]?.command] | any(test("sessync hook start"))' "$T/dotfiles/s2.json"
rm "$s"; printf '{ "model": "opus", сломано\n' > "$s"
check "install.sh: settings.json с ошибкой — отказ" not inst install.sh
check "install.sh: settings.json с ошибкой не тронут" grep -q 'сломано' "$s"

echo
if [ "$fails" -eq 0 ]; then echo "Все проверки прошли"; else echo "Не прошло: $fails"; exit 1; fi
