# Changelog

## 2.1.0 — 2026-10-11

- A session continued on two Macs between syncs now splits the way Claude Code's own `/branch`
  does: one branch keeps the session, the other becomes a session of its own, "<title> (Branch)",
  that `/resume`, `claude -r` and `sessync find` see. Before, the other version was a
  `<id>.jsonl.conflict1` copy that Claude Code didn't show. Every Mac makes the same branch, and a
  Mac whose branch already became a session appends to it instead of splitting again. A
  continuation of only Claude Code's service lines (a session opened and closed) is not worth a
  branch and is dropped. Other files still get `.conflictN` copies.
- The file of a session open in `claude` on this Mac is no longer changed: Claude Code works from
  what it read, and lines put under it would split the conversation inside the file, with one
  branch hidden. Lines from another Mac wait until the session closes; the end hook waits for
  `claude` to exit, then syncs.
- `claude -r` on a Mac with an older copy of the session: the start hook syncs first (Claude's first
  answer waits for hooks anyway, 20 s at most) and shows a warning with the command to open the
  latest version.
- `sessync` run by hand while a sync is running waits for it and then syncs, instead of leaving.
- `sessync conflicts` and `sessync status` list the sessions that split.
- Notifications pass their text to `osascript` as an argument, not inside the script.

## 2.0.1 — 2026-10-10

- Security: nothing is written outside `~/.claude/projects`. A path from the storage with `..` is
  skipped; a file is not written through a link to a folder elsewhere (links arrive from the storage
  as they are), checked right before each write, so a link received in the same sync counts too;
  a file that is itself a link here is not written through. Writing such things into the storage
  takes the encryption password, so this closes the way from one compromised Mac to the others.
  `sessync restore` checks the same.

## 2.0.0 — 2026-10-10

The tool is now **sessync** and is ready for other people's Macs.

- Homebrew: `brew install latark/tap/sessync`.
- One command: `sessync` (sync), `sessync find` (was `cc-find`), `sessync status`, … `install.sh`
  replaces the old `cc-sync`/`cc-find` links and hooks.
- English interface; Russian when the system language is Russian (`LANGUAGE=` in the config).
- Settings in `~/.config/sessync/config`, state in `~/.local/state/sessync/`, search index in
  `~/.cache/sessync/find` — no longer inside `~/.claude`. The status-line files keep their format.
- `sessync setup` asks where to keep the sessions: Cloudflare R2, Backblaze B2, Amazon S3, any
  S3-compatible service, or any rclone remote (Google Drive, Dropbox, OneDrive, SFTP, WebDAV…).
  No provider is assumed by default.
- Different user names on different Macs: the storage remembers the first Mac's home folder, and
  project folders (and project paths in the prompt history) are mapped between home folders.
- `sessync hooks install | remove`; the hook calls the installed command (Homebrew or
  `~/.local/bin`). `sessync setup` offers to add them.
- `sessync setup` and `sessync export` are tested in a terminal, for every kind of storage.
- `SESSYNC_PYTHON` picks the Python interpreter.
- Removed: the migration from 1.3 (rclone bisync).

## 1.4.1 — 2026-10-10

- A new base also removes tails that are off the chain.
- An attachment changed the same way on two Macs is not a conflict.
- Sessions verified after the move to 1.4 are checked by size and time from then on.
- Temporary files of interrupted runs are cleaned up after an hour.

## 1.4.0 — 2026-10-10

- Own sync engine instead of rclone bisync: a transcript is a base plus appended tails, so only new
  lines travel, Litestream-style. Tails are folded when a session goes quiet; a new base is sent when
  the tails grow as big as the base.
- Storage format 2 (in the check file); older versions stop on it.

## 1.3.0 and earlier

- rclone bisync with crypt, the trash, the mass-deletion stop (`deletes --undo/--apply`), retention
  fix, prompt-history merge, search, status line, `export` to the Passwords app.
