#!/bin/bash
# Removes sessync from this Mac: the hooks in settings.json, the command in ~/.local/bin, the
# background loop. The data in the storage, local sessions and cleanupPeriodDays stay.
#   ./uninstall.sh           — keep the keys and password in the Keychain and the storage settings
#   ./uninstall.sh --purge   — remove them too, and the local state and search index
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
conf="${XDG_CONFIG_HOME:-$HOME/.config}/sessync/config"
st="${XDG_STATE_HOME:-$HOME/.local/state}/sessync"
ru() { case "${SESSYNC_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}" in ru*) return 0 ;; *) return 1 ;; esac; }
say() { if ru; then echo "$2"; else echo "$1"; fi; }

if [ -f "$st/loop.pid" ]; then
  pid=$(cat "$st/loop.pid")
  ps -o command= -p "$pid" 2>/dev/null | grep -q 'sessync _loop' && kill "$pid" \
    && say "-- background loop stopped" "-- фоновый цикл остановлен"
  rm -f "$st/loop.pid"
fi

command -v jq >/dev/null && "$here/bin/sessync" hooks remove

[ -L "$HOME/.local/bin/sessync" ] && rm "$HOME/.local/bin/sessync" && say "-- command removed: sessync" "-- убрана команда sessync"

if [ "${1:-}" = --purge ]; then
  svc=sessync
  [ -f "$conf" ] && svc=$(sed -n 's/^KEYCHAIN_SERVICE=//p' "$conf" | tail -1) && svc=${svc:-sessync}
  for a in s3-access-key s3-secret-key passphrase; do
    security delete-generic-password -s "$svc" -a "$a" >/dev/null 2>&1 \
      && say "-- removed from the Keychain: $a" "-- из Связки ключей удалено: $a"
  done
  rm -rf "$st" "$conf" "${XDG_CACHE_HOME:-$HOME/.cache}/sessync"
  say "-- storage settings, local state and the search index removed" "-- удалены настройки хранилища, локальное состояние и индекс поиска"
  say "!! If the encryption password is not saved anywhere else, the data in the storage can't be decrypted now." \
    "!! Если пароль шифрования нигде больше не сохранён, архив в хранилище теперь не расшифровать."
fi
say "Done. The data in the storage is untouched — delete it in your provider's console if needed." \
  "Готово. Данные в хранилище не тронуты — удалить их можно в панели провайдера."
