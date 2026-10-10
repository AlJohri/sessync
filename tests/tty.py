"""Runs a command in a terminal, the way a person would: waits for each prompt, then types the answer.
For the interactive commands (setup, export), which refuse to run without a terminal.

  tests/tty.py ACTION… -- COMMAND…

Actions, in order:
  --expect TEXT   wait until TEXT appears in the output after the previous match (15 s at most)
  --send TEXT     type TEXT and Enter ("" — just Enter)
  --secret TEXT   the same, but first wait until the terminal stops echoing (read -s), as a person
                  pasting a password would — so the test sees whether the secret could be on screen
  --run CMD       run CMD with bash at this point (for example, read the clipboard between steps)

Prints everything the command printed and exits with its code; 124 if an --expect timed out.
"""
import os
import select
import subprocess
import sys
import termios
import time

WAIT = 15


def main():
    i = sys.argv.index("--")
    acts, cmd = sys.argv[1:i], sys.argv[i + 1:]
    master, slave = os.openpty()
    p = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    out = bytearray()

    def pump(t):
        r, _, _ = select.select([master], [], [], t)
        if r:
            try:
                out.extend(os.read(master, 65536))
            except OSError:
                pass

    def give_up(why):
        p.kill()
        p.wait()
        pump(0.1)
        sys.stdout.buffer.write(bytes(out))
        print(f"\ntty.py: {why}", file=sys.stderr)
        sys.exit(124)

    pos = 0
    for k in range(0, len(acts), 2):
        act, arg = acts[k], acts[k + 1]
        if act == "--expect":
            want, end = arg.encode(), time.time() + WAIT
            while out.find(want, pos) < 0:
                if p.poll() is not None:
                    pump(0.2)
                    if out.find(want, pos) < 0:
                        give_up(f"the command ended before {arg!r}")
                    break
                if time.time() > end:
                    give_up(f"no {arg!r} in {WAIT} s")
                pump(0.1)
            pos = out.find(want, pos) + len(want)
        elif act in ("--send", "--secret"):
            end = time.time() + WAIT
            while act == "--secret" and termios.tcgetattr(slave)[3] & termios.ECHO:
                if time.time() > end:
                    give_up("the terminal still echoes input: a secret would be on screen")
                time.sleep(0.02)
            os.write(master, arg.encode() + b"\r")
        elif act == "--run":
            subprocess.run(["bash", "-c", arg], check=False)
        else:
            sys.exit(f"tty.py: unknown action {act}")
    end = time.time() + WAIT
    while p.poll() is None:
        if time.time() > end:
            give_up("the command did not end")
        pump(0.1)
    pump(0.2)
    sys.stdout.buffer.write(bytes(out))
    sys.exit(p.returncode)


main()
