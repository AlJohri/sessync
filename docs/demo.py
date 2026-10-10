"""Records docs/demo.gif: two "Macs" in the test mode of sessync (a local folder instead of the
storage), sessions made up for the demo, real commands with their real output.

  python3 docs/demo.py        needs agg: brew install agg (KEEP=1 — keep the temporary folder)
"""
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
W, H = 96, 11
SID = "7c9e6b1a-2f4d-4c1e-9a55-3d8f0b2c41e7"
rnd = random.Random(7)


def enc(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


class Mac:
    def __init__(self, tmp, name, host):
        self.tmp, self.name, self.host = tmp, name, host
        self.home = tmp / "ann"
        self.claude = tmp / name / "claude"
        (self.claude / "projects").mkdir(parents=True)
        (self.claude / "settings.json").write_text('{"cleanupPeriodDays": 36500}\n')
        conf = tmp / name / "config" / "sessync"
        conf.mkdir(parents=True)
        (conf / "config").write_text("BUCKET=sessions\nLANGUAGE=en\n")

    def env(self):
        e = dict(os.environ)
        e.update(HOME=str(self.home), CLAUDE_CONFIG_DIR=str(self.claude),
                 XDG_CONFIG_HOME=str(self.tmp / self.name / "config"),
                 XDG_STATE_HOME=str(self.tmp / self.name / "state"),
                 XDG_CACHE_HOME=str(self.tmp / self.name / "cache"),
                 SESSYNC_HOST=self.name, SESSYNC_TEST_REMOTE=str(self.tmp / "storage"),
                 SESSYNC_TEST_PASSPHRASE="demo-password-123456", SESSYNC_LANG="en",
                 RCLONE_CONFIG=str(self.tmp / "rclone.conf"), TERM="xterm-256color")
        return e

    def session(self, project, sid, title, day, turns):
        cwd = str(self.home / "projects" / project)
        os.makedirs(cwd, exist_ok=True)
        f = self.claude / "projects" / enc(cwd) / f"{sid}.jsonl"
        f.parent.mkdir(parents=True, exist_ok=True)
        lines = [{"type": "ai-title", "aiTitle": title, "sessionId": sid}]
        for i, (role, text) in enumerate(turns):
            content = text if role == "user" else [{"type": "text", "text": text}]
            lines.append({"type": role, "message": {"role": role, "content": content}, "cwd": cwd,
                          "sessionId": sid, "timestamp": f"{day}T15:{40 + i:02d}:10Z"})
        with open(f, "a") as out:
            for d in lines:
                out.write(json.dumps(d, separators=(",", ":")) + "\n")  # compact, like Claude Code

    def run(self, *args):
        """sessync in a terminal (colours on), as the demo shows it."""
        cmd = [sys.executable, "-I", str(REPO / "tests/tty.py"), "--", str(REPO / "bin/sessync"), *args]
        r = subprocess.run(cmd, env=self.env(), capture_output=True, check=True)
        return r.stdout.decode()


class Cast:
    def __init__(self):
        self.t, self.events = 0.0, []

    def out(self, s, dt=0.0):
        self.t += dt
        self.events.append([round(self.t, 3), "o", s])

    def type(self, s):
        for ch in s:
            self.out(ch, rnd.uniform(0.04, 0.10))

    def scene(self, caption):
        self.out("\x1b[2J\x1b[3J\x1b[H\x1b[2m" + caption + "\x1b[0m\r\n\r\n", 0.6)

    def command(self, mac, typed, output, pause=1.6):
        self.out(f"\x1b[1;32mann@{mac.host}\x1b[0m \x1b[1;34m~\x1b[0m % ", 0.5)
        self.type(typed)
        if output is None:
            self.t += pause
            return
        self.out("\r\n", 0.35)
        self.out(output, 0.5)
        self.t += pause

    def save(self, path):
        with open(path, "w") as f:
            f.write(json.dumps({"version": 2, "width": W, "height": H,
                                "env": {"SHELL": "/bin/zsh", "TERM": "xterm-256color"}}) + "\n")
            for e in self.events:
                f.write(json.dumps(e) + "\n")


def record(tmp):
    (tmp / "storage" / "sessions").mkdir(parents=True)
    (tmp / "rclone.conf").write_text("")
    air, mini = Mac(tmp, "air", "MacBook-Air"), Mac(tmp, "mini", "Mac-mini")
    air.session("blog", "0b6f2c1e-8a9d-4f5e-b7c3-1d2e3f4a5b6c", "Move the blog from Jekyll to Astro",
                "2026-10-06", [("user", "Move the blog from Jekyll to Astro and keep every URL working."),
                               ("assistant", "Done: content collections for posts, redirects for the old "
                                             "/YYYY/MM/ paths, the RSS feed at the same address.")])
    air.session("shop-api", "5d4c3b2a-1f0e-4d9c-8b7a-6e5f4d3c2b1a", "Fix the flaky checkout tests",
                "2026-10-08", [("user", "The checkout tests fail every few runs. Find out why."),
                               ("assistant", "They shared one Postgres schema; each test now gets its "
                                             "own transaction that is rolled back.")])
    air.run()
    mini.run()
    air.session("shop-api", SID, "Rate limiting for the checkout API", "2026-10-10",
                [("user", "Bots hammer POST /checkout. Add rate limiting, 30 requests a minute per API key."),
                 ("assistant", "A token bucket per API key in Redis: INCR on a per-minute key with EXPIRE, "
                               "and 429 with a Retry-After header over the limit. Added "
                               "middleware/rate_limit.py and tests."),
                 ("user", "Also exempt our own health checks.")])

    c = Cast()
    c.scene("# MacBook Air: a Claude Code session just ended — sessync runs by itself, or by hand:")
    c.command(air, "sessync", air.run())
    c.scene("# Later, on the Mac mini:")
    c.command(mini, "sessync", mini.run())
    c.command(mini, "sessync find rate limit", mini.run("find", "rate", "limit"), pause=3.5)
    c.command(mini, f"cd ~/projects/shop-api && claude -r {SID}", None, pause=3.5)
    cast = tmp / "demo.cast"
    c.save(cast)
    subprocess.run(["agg", "--quiet", "--theme", "github-dark", "--font-size", "15", "--idle-time-limit", "4",
                    "--last-frame-duration", "4", str(cast), str(REPO / "docs/demo.gif")], check=True)


def main():
    if not shutil.which("agg"):
        sys.exit("agg is needed: brew install agg")
    tmp = Path(tempfile.mkdtemp(prefix="sessync-demo."))
    try:
        record(tmp)
    finally:
        if os.environ.get("KEEP"):
            print(f"kept: {tmp}")
        else:
            shutil.rmtree(tmp)


main()
