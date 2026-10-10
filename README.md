# sessync

[![tests](https://github.com/latark/sessync/actions/workflows/test.yml/badge.svg)](https://github.com/latark/sessync/actions/workflows/test.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)

**Your Claude Code sessions on every Mac.** Continue a conversation you started on another computer
(`claude -r`), and search your whole history (`sessync find`). Sessions live in storage you own —
Cloudflare R2, Backblaze B2, Amazon S3, any S3-compatible service, or anything
[rclone](https://rclone.org) can reach — and are encrypted on your Mac before they leave it.

[Русская версия](README.ru.md)

![sessync: a session from the MacBook Air found and continued on the Mac mini](docs/demo.gif)

Claude Code keeps each session in `~/.claude/projects/<project>/<id>.jsonl` on the machine where it
ran, and deletes sessions after 30 days by default. There is no built-in sync.

## What you get

- **Automatic.** sessync syncs when a `claude` session starts and ends, and every 10 minutes while
  one is open. When the last session closes, nothing runs in the background: no launchd, no login
  items.
- **Resume anywhere.** `claude -r <id>` and `/resume` on one Mac see the sessions from the others.
- **Only new lines travel.** A session is a log that only grows, so sessync ships it like a database
  log ([Litestream](https://litestream.io/how-it-works/)-style): a session of hundreds of megabytes
  that you are working in sends kilobytes per sync, not itself.
- **Nothing gets lost.** A session changed on two Macs between syncs keeps the longer version under
  its name and the other one as a copy next to it. A truncated or damaged transcript never
  overwrites a full one. Deleted sessions stay in a trash for 30 days. If more than half of the
  files are about to be deleted at once, sync stops and asks you.
- **Search.** `sessync find words` finds the sessions where something was discussed and prints the
  command to continue each.
- **Retention.** sessync raises Claude Code's `cleanupPeriodDays` to 100 years and brings back from
  the storage what Claude Code already deleted.
- **Shared prompt history** (the ↑ key) across your Macs.
- **Different user names** on different Macs are fine: project folders are mapped between home
  folders.

## How it compares

| | sessync | [claude-sync](https://github.com/tawanorg/claude-sync) | [claude-code-sync](https://github.com/perfectra1n/claude-code-sync) | Syncthing / Dropbox |
|---|---|---|---|---|
| What is sent | only appended lines | whole files, compressed | whole files, into git | whole files |
| Sessions over 100 MB | yes | can't be downloaded back | via Git LFS | yes |
| A truncated copy overwrites the full one | no, it's a conflict | can happen | — | can happen |
| Two Macs changed one session | longer one kept, the other saved as a copy | `.conflict` copy | smart merge | conflict copies |
| Prompt history | merged line by line | last writer wins | optional | conflict copies |
| Deletions | trash for 30 days, mass-deletion stop, open sessions kept | deleted at once | mirrored with guards | deleted at once |
| Encryption | contents and file names | contents | none (use an encrypted repo) | provider's |
| Runs | by itself (Claude Code hooks) | `push` / `pull` by hand | by hand or cron | by itself |
| Search | `sessync find` | — | — | — |
| Platforms | macOS (Linux planned) | macOS, Linux, Windows | macOS, Linux, Windows | all |

## Requirements

- macOS, [Homebrew](https://brew.sh), the Claude Code CLI.
- Storage: a private bucket (Cloudflare R2's free tier — 10 GB, no download fees — is plenty for
  years of sessions) or any rclone remote.

## Install

```bash
brew install latark/tap/sessync
```

Or from git (update with `git pull`):

```bash
git clone https://github.com/latark/sessync.git ~/projects/sessync
~/projects/sessync/install.sh
```

`install.sh` installs rclone, ripgrep and jq, links the `sessync` command into `~/.local/bin`, adds
two hooks to `~/.claude/settings.json` and raises the session retention (`cleanupPeriodDays`). The
previous `settings.json` is kept next to it as `settings.json.bak-sessync-…`. Don't move the folder
afterwards: the command is a link into it.

Then, in a regular terminal (not with `!` inside Claude — the input must not land in a transcript):

```bash
sessync setup     # storage, keys, encryption password, the Claude Code hooks
sessync           # first sync
sessync export    # save the keys and the password to the Passwords app, step by step
```

**Storage.** `sessync setup` offers Cloudflare R2, Backblaze B2, Amazon S3, any S3-compatible
service (by its endpoint), or any rclone remote — Google Drive, Dropbox, OneDrive, SFTP,
WebDAV/Nextcloud, a NAS — that you set up with `rclone config` first. For a bucket, create a
**private** one used only for sessions, and an access key limited to it.

**The encryption password is the only way to read the data.** Lose it, and the storage stays
unreadable forever. On the first Mac press Enter to get a random one, then run `sessync export`: it
opens the Passwords app and walks you through saving the keys and the password, putting them one by
one into the clipboard of this Mac only (no Universal Clipboard, marked concealed so clipboard
managers skip them) and clearing it at the end. The entry reaches your other devices through iCloud.

### Your other Macs

1. Install the same way.
2. `sessync setup` — the same storage, keys and **the same password** (from the Passwords entry).
   With another password sessync refuses to work and writes nothing.
3. `sessync` — downloads everything.

## Use

Usually — not at all: it happens by itself. To switch Macs, run `sessync` on the first one (or just
close `claude`), start `claude` on the second, and the sessions show up in `/resume`. Or find one:

```bash
sessync find lease contract     # sessions where the conversation has all these words
sessync find "exact phrase"
sessync find -p my-site deploy  # only projects with my-site in the path
sessync find                    # latest sessions in all projects
```

Each result shows when, in which folder, the title, a snippet and a ready command like
`cd ~/projects/my-site && claude -r 3bb6f76a-…`. The search covers the conversation itself — your
messages and Claude's answers, not the injected service text or tool output (`--raw` includes them).

| Command | What it does |
|---|---|
| `sessync` | sync now |
| `sessync status` | what was synced and when, errors, conflicts; `--remote` — size in the storage |
| `sessync find …` | search all sessions |
| `sessync off` / `on` | turn automatic sync off / on |
| `sessync conflicts` | sessions changed on two Macs (`--delete` — delete the copies) |
| `sessync trash` | deleted sessions in the storage trash |
| `sessync restore <id>` | bring a session back from the trash |
| `sessync deletes` | sync stopped because of a mass deletion: `--undo` brings back, `--apply` deletes everywhere |
| `sessync setup` | storage (`--storage` to change it), keys, password |
| `sessync export` | save the keys and password to Passwords |
| `sessync hooks install` / `remove` | the Claude Code hooks |
| `sessync log` | last lines of the log |

The interface is in English, or in Russian when your system language is Russian
(`LANGUAGE=en` or `LANGUAGE=ru` in `~/.config/sessync/config` to choose).

## Status line

If you have your own `statusLine` in `settings.json`, add `$(sessync statusline)` to its output.
If not, you can show just the sync:

```json
"statusLine": { "type": "command", "command": "sessync statusline" }
```

`sessions ↻ 13:26` (dim) — all good, time of the last sync, yellow if over 30 minutes ago;
`sessions: <what happened>` (yellow) — an error; `sessions: conflict N` (red);
`sessions: sync off`. Errors and new conflicts also come as a macOS notification, once.

## Tell Claude about it

Add to `~/.claude/CLAUDE.md`, so Claude in any project knows the archive is there:

```markdown
## Session history across Macs
- sessync syncs the sessions of all my Macs (encrypted storage). Find past conversations from any
  project with `sessync find word …` (`--raw` also searches tool output); continue one with
  `cd <folder> && claude -r <id>`.
- Never put transcripts (`~/.claude/projects/**/*.jsonl`) or `~/.claude/history.jsonl` into git or
  publish them: they hold whole conversations, including files with keys that were read.
- The storage keys and the encryption password are in the Keychain: never print their values into
  the chat or logs. They are entered only with `sessync setup` in my own terminal.
```

## Different user names

Claude Code names a project folder after its full path (`/Users/ann/work/site` →
`-Users-ann-work-site`). The storage remembers the home folder of the first Mac; on a Mac with
another one (`/Users/bob`), project folders under it are renamed on the way in and out, and so are
project paths in the prompt history. Transcript text stays byte for byte as it was (old messages
mention the other path, which doesn't affect resuming). Projects outside the home folder need the
same path on all Macs. Very long paths, which Claude Code shortens with a hash, can't be mapped.

## Trash

A session deleted on any Mac is first copied into `trash/<date>/` inside the same storage — no
download, encrypted like everything else — and only then deleted. After 30 days the copy goes
(`TRASH_DAYS=…` in the config).

```bash
sessync trash               # what is in the trash and when it was deleted
sessync restore 3bb6f76a    # bring a session back (id or part of the path), with its attachments
sessync                     # it returns to the storage and your other Macs
```

Old versions of sessions are not kept: a transcript only grows, and each version contains the
previous one whole.

## Looking through and deleting sessions

- `claude --resume`: `Ctrl+A` — all projects, Space — preview, `Ctrl+R` — rename.
- [Agent Sessions](https://github.com/jazzyalex/agent-sessions) — a macOS app to read old
  conversations in full. It only reads transcripts. On the first screen turn off "Enable Quota
  Meter" if you don't need limits (otherwise it reads Claude Code's login token from the Keychain),
  and don't enable its tmux probe: it starts `claude` in its own folder, and sessync would carry those
  service sessions to all your Macs.
- Delete a whole project: `claude purge <folder>` (built into Claude Code). It is deleted on your
  other Macs too and stays in the trash for 30 days.
- Delete one session: the `<id>.jsonl` file and the `<id>/` folder next to it (subagents,
  attachments).

## Security

In short: contents and file names are encrypted on your Mac with rclone crypt; the storage sees
encrypted objects, their sizes and times. Keys and the password live in the Keychain. Everything
sessync writes on disk is readable by your user only. Details and the threat model:
[SECURITY.md](SECURITY.md).

## Limitations

- macOS only for now. Linux is next.
- Sync is not instant: at session start and end and every 10 minutes. Run `sessync` before
  switching.
- Don't continue the same session on two Macs at the same time.
- A deletion on one Mac reaches the others (and the trash keeps a copy for 30 days).
- Only sessions and prompt history are synced. Settings, plugins, skills, `/rewind` checkpoints and
  `memory/` folders are not — keep those in a git repository of your `~/.claude`.
- It relies on Claude Code only appending to transcripts. If that changes, sessync has to change too.

## Troubleshooting

| In the status line / `sessync status` | What to do |
|---|---|
| `not set up (sessync setup)` | run `sessync setup` in a terminal |
| `no access to the storage …` | network, bucket name, keys (`sessync setup`), the provider's billing |
| `the encryption password is not the one used on your other Macs` | `sessync setup`, the password from Passwords |
| `settings.json can't be read` | `~/.claude/settings.json` has an error; `jq . ~/.claude/settings.json` shows where |
| `did not finish (code …)` | usually the network; it retries itself; details — `sessync log` |
| `stopped: too many deletions` | `sessync deletes` shows what and where; by mistake — `--undo`, on purpose — `--apply` |
| `the storage is in a newer format` | another Mac runs a newer sessync: update this one |
| `sessions ↻ …` in yellow | no sync for a while: `sessync status`, maybe no network |

The log is `~/.local/state/sessync/sync.log`.

## Uninstall

```bash
./uninstall.sh            # hooks and the command go; keys, password and the data stay
./uninstall.sh --purge    # also the keys and password from the Keychain, local state, search index
```

With Homebrew: `$(brew --prefix sessync)/libexec/uninstall.sh` (add `--purge` if you like), then
`brew uninstall sessync`.

The data in the storage is untouched — delete the bucket in your provider's console if you don't
need it. `cleanupPeriodDays` stays; set it back to 30 if you want old sessions deleted again.

## How it works

- Everything in the storage is encrypted with `rclone crypt`: contents and names. `lib/engine.py`
  (python3, no dependencies) does the sync on top of rclone. `memory/` folders are not synced.
- **Transcripts** (`*.jsonl`) only grow, so they travel as a log. In the storage a session is a
  **base** (a full copy at some point) and **tails** — objects with the lines appended after it.
  Only new whole lines are sent; another Mac downloads only new tails and appends them to its file,
  or reads the slice it needs from the middle (crypt can be read from any offset).

  ```
  Mac A    session.jsonl   ████████████████████████▒▒░
  storage                  [ base 9.4 MB           ][tail][tail]   ← each sync adds one tail
  Mac B    session.jsonl   ████████████████████████▒   + the new tail → the same bytes
  ```
- **Compaction** is done by the Mac that appended last. A session quiet for an hour gets its tails
  folded into one; 48 tails are folded even while it runs; when the tails grow as big as the base,
  the session goes whole as a new base. Each base is at least twice the previous one, so a session
  costs at most two of its sizes in uploads overall.
- **Attachments** (tool output, images, conflict copies) are written once and go whole. Symlinks
  (subagents) go as links.
- **Conflicts.** Changed on two Macs between syncs — the longer version keeps the name, the other
  becomes `<id>.jsonl.conflict1` next to it. A transcript that got shorter is a conflict too.
- **Deletions.** What is deleted here is copied to the trash first. A session deleted on another
  Mac but open here (Claude Code's registry `~/.claude/sessions/`) is deleted here after it closes.
- **Prompt history.** Each Mac has its own file in the storage (Mac name + start of its hardware
  UUID), only appended to; on each Mac all files are merged line by line, without repeats.
- **Format.** The storage format is in a check file. A newer format stops older versions instead of
  letting them write the old way.
- **This Mac's state** — `~/.local/state/sessync/` (log, status marks, engine state); settings —
  `~/.config/sessync/config`; search index — `~/.cache/sessync/find`.
- **Tests** — `tests/run.sh`: several "Macs" and a local folder instead of the storage; doesn't
  touch the Keychain or the real `~/.claude`.

---

sessync is an independent project, not affiliated with or endorsed by Anthropic. "Claude" and
"Claude Code" are trademarks of Anthropic. MIT license.
