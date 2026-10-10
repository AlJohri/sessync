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
  prompts, the log, the search index — gets 600/700 permissions, like Claude Code's own files.
- **Your terminal is safe from transcript text.** `sessync find` strips control characters (ESC/OSC
  sequences, BEL, bidi) before printing, so command output or page text stored in a transcript can't
  run in your terminal.
- **Mistakes are recoverable.** Deleted sessions stay in the trash for 30 days; a mass deletion
  stops the sync until you decide; a truncated transcript never overwrites a full one.

## What the storage can see

- The number of objects, their sizes (plus a small fixed overhead) and upload times — so, roughly,
  when you work and how much.
- The folder nesting (names are encrypted, the depth is not), and the name of the check file
  `v1-check/keycheck` (its contents are encrypted).

## What sessync doesn't protect against

- Someone with access to your unlocked Mac, or software running as your user: sessions lie there in
  the clear, as they do without sessync, and the Keychain hands secrets to your own processes.
- A weak encryption password. On the first Mac sessync creates a random 32-character one; if you
  choose your own, make it long. rclone crypt uses its built-in salt (sessync doesn't set
  `password2`), so the password is the only secret.
- Losing the encryption password. Nobody — not the provider, not this project — can read the data
  without it. Save it with `sessync export` or in your password manager.

## Storage keys

Give sessync a key limited to one private bucket used only for sessions — not your account's main
key, which opens all your buckets. With an rclone remote (Google Drive, Dropbox…), sessync uses the
access you configured in `rclone config`; the data is still encrypted by sessync.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting: the **Security** tab of this repository →
**Report a vulnerability**. Don't open a public issue for it.
