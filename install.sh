#!/bin/bash
# Installs sessync from this folder: dependencies, the sessync command in ~/.local/bin, Claude Code
# hooks in ~/.claude/settings.json and a long session retention. Safe to run again.
# Keys and the encryption password come later: sessync setup, in your own terminal.
# With Homebrew instead: brew install latark/tap/sessync && sessync setup
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
bin="$HOME/.local/bin"
ru() { case "${SESSYNC_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}}" in ru*) return 0 ;; *) return 1 ;; esac; }
say() { if ru; then echo "$2"; else echo "$1"; fi; }

[ "$(uname)" = Darwin ] || { say "macOS only for now (Keychain, osascript)" "Пока только macOS (Связка ключей, osascript)"; exit 1; }

say "== 1/3 Dependencies: rclone, ripgrep, jq" "== 1/3 Зависимости: rclone, ripgrep, jq"
if [ -z "${SESSYNC_SKIP_BREW:-}" ]; then
  command -v brew >/dev/null || { say "Homebrew is needed: https://brew.sh" "Нужен Homebrew: https://brew.sh"; exit 1; }
  # package:command — a command already available (from anywhere) is not installed again
  for p in rclone:rclone ripgrep:rg jq:jq; do
    command -v "${p#*:}" >/dev/null || brew install "${p%%:*}"
  done
fi
command -v python3 >/dev/null || { say "python3 is needed: xcode-select --install" "Нужен python3: xcode-select --install"; exit 1; }

say "== 2/3 The sessync command in $bin" "== 2/3 Команда sessync в $bin"
mkdir -p "$bin"
ln -sf "$here/bin/sessync" "$bin/sessync"
# Before 2.0 the tool was cc-sync and cc-find: their links into this folder go
for t in cc-sync cc-find; do
  if [ -L "$bin/$t" ]; then
    case "$(readlink "$bin/$t")" in "$here"/*|*/claude-session-sync/*) rm "$bin/$t" ;; esac
  fi
done
case ":$PATH:" in
  *":$bin:"*) ;;
  *) say "!! $bin is not on PATH — add to ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" \
       "!! $bin нет в PATH — добавьте в ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

say "== 3/3 Claude Code hooks and session retention" "== 3/3 Хуки Claude Code и срок хранения сессий"
SESSYNC_BIN="$bin/sessync" "$here/bin/sessync" hooks install

echo
if "$bin/sessync" status 2>/dev/null | grep -q 'sessync setup'; then
  say "Next: in your own terminal, sessync setup, then sessync" "Дальше: в своём терминале sessync setup, затем sessync"
else
  say "Done. Check: sessync status" "Готово. Проверить: sessync status"
fi
