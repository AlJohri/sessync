# Changelog

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
