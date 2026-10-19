# Security

Claude Code transcripts hold whole conversations: the contents of files Claude read, command output,
sometimes API keys from a `.env`. sessync is built so that the storage never sees any of it.

## What is protected

- **The storage provider, and anyone who gets your storage keys, sees only ciphertext.** Everything
  is encrypted on your Mac with [rclone crypt](https://rclone.org/crypt/) before upload: file
  contents (NaCl SecretBox — XSalsa20 + Poly1305, in 64 KiB chunks) and file and folder names
  (EME with AES-256). The key comes from your encryption password through scrypt.
- **A wrong password can't damage the archive.** A check file encrypted with the same password is
  read before any write; with another password sessync stops and writes nothing, so a second,
  unreadable copy can't appear.
- **Secrets stay in the Keychain.** The storage keys and the encryption password are written there
  through `security -i` and stdin (not in a command line, so not in the process list), and passed to
  rclone through its environment. They are never printed, logged or written to files. `sessync
  export` puts them into the clipboard of this Mac only (no Universal Clipboard), marked as concealed
  and transient so clipboard managers skip them, and clears it at the end.
- **Local files are owner-only.** Everything sessync writes — downloaded sessions, other Macs'
  prompts, the log, the search index — gets 600/700 permissions, like Claude Code's own files. The
  copies of session text that a sync stages on the way to and from the storage are deleted when the
  sync ends.
- **Nothing is written outside the projects folder.** Even a Mac that has the password (and so can
  write anything into the storage) can't make sessync write elsewhere on your other Macs: paths
  with `..` are skipped, and nothing is written through a link to a folder outside
  `~/.claude/projects` (subagent links come from the storage as they are).
- **Your terminal is safe from transcript text.** `sessync find` strips control characters (ESC/OSC
  sequences, BEL, bidi) before printing, so command output or page text stored in a transcript can't
  run in your terminal. Session titles shown by `sessync conflicts` are cleaned the same way, and
  notifications pass their text to `osascript` as an argument, never as part of the script.
- **Mistakes are recoverable.** Deleted sessions stay in the trash for 30 days, also the ones
  deleted everywhere with `sessync forget` (unless you add `--now`); a mass deletion stops the sync
  until you decide; a truncated transcript never overwrites a full one.

## What the storage can see

- The number of objects, their sizes (plus a small fixed overhead) and upload times — so, roughly,
  when you work and how much.
- The folder nesting (names are encrypted, the depth is not), and the name of the check file
  `v1-check/keycheck` (its contents are encrypted).
- That a session was deleted with `sessync forget`, and when: a small object whose name (the
  session id) is encrypted stays as a mark, so the other Macs delete it too.

## What sessync doesn't protect against

- Someone with access to your unlocked Mac, or software running as your user: sessions lie there in
  the clear, as they do without sessync, and the Keychain hands secrets to your own processes.
- A weak encryption password. On the first Mac sessync creates a random 32-character one; if you
  choose your own, make it long. rclone crypt uses its built-in salt (sessync doesn't set
  `password2`), so the password is the only secret.
- Losing the encryption password. Nobody — not the provider, not this project — can read the data
  without it. Save it with `sessync export` or in your password manager.

## Deleting a conversation for good

`sessync forget <id> --now` deletes a session and its prompts from this Mac, the storage and its
trash, and from your other Macs as they sync (see the README). What no tool on your Mac can delete:

- what reached Anthropic during the conversation — it is kept under Anthropic's policies;
- copies in your backups, such as Time Machine;
- old versions at the provider, if the bucket keeps them: turn object versioning off, and on
  Backblaze B2 set the bucket's lifecycle to "keep only the last version" (by default B2 keeps all
  versions of a deleted file). These versions are encrypted like everything else;
- a Mac that is offline: it deletes its copy when it syncs next.

## Storage keys

Give sessync a key limited to one private bucket used only for sessions — not your account's main
key, which opens all your buckets. With an rclone remote (Google Drive, Dropbox…), sessync uses the
access you configured in `rclone config`; the data is still encrypted by sessync.

## Storage of your own, without encryption

`ENCRYPT=off` (only offered for `STORAGE=ssh`, a folder on a machine of your own) turns all of the
above off for the storage: sessions, their names and the prompt history lie there in plain text,
readable by anyone who can read that folder or that machine's backups. Use it only when the
storage machine is as trusted as the ones that sync with it. Mixing is refused: a machine with
encryption on finds no check file it can decrypt, and one with it off finds `keycheck.bin`
instead of `keycheck`, so neither writes.

On Linux, secrets (when there are any) go to the Secret Service keyring through `secret-tool`,
given on stdin, not in a command line.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting: the **Security** tab of this repository →
**Report a vulnerability**. Don't open a public issue for it.
