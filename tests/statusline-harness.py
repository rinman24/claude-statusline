"""Render the status line across cases and assert the width rules.

usage: python3 tests/statusline-harness.py [<checkout>] [--show]

<checkout> defaults to the repo this file lives in; pass another clone or
worktree to test its statusline.sh.
"""
import itertools, json, os, re, subprocess, sys, time, unicodedata

args = [a for a in sys.argv[1:] if not a.startswith("--")]
root = args[0] if args else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
show = "--show" in sys.argv
script = os.path.join(root, "statusline.sh")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
BAR = re.compile(r"[█░]+")


def dw(s):
    s = ANSI.sub("", s)
    return sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s)


def payload(tokens, window, line1, limits, five, note7):
    now = int(time.time())
    d = {"model": {"display_name": "Opus 5.5"},
         "context_window": {"total_input_tokens": tokens, "context_window_size": window},
         "cost": {"total_cost_usd": 1.23}}
    if line1 == "long":
        d["effort"] = {"level": "high"}
        d["thinking"] = {"enabled": True}
        d["output_style"] = {"name": "Explanatory"}
        d["workspace"] = {"current_dir": root, "git_worktree": "feat+statusline-size-presets"}
    elif line1 == "mid":
        d["effort"] = {"level": "high"}
        d["workspace"] = {"current_dir": "/tmp/dotfiles"}
    rl = {}
    if limits in ("both", "5h"):
        rl["five_hour"] = {"used_percentage": five, "resets_at": now + 8100}
    if limits == "both":
        rl["seven_day"] = {"used_percentage": 18.4}
        if note7:
            rl["seven_day"]["resets_at"] = now + 300000
    if rl:
        d["rate_limits"] = rl
    return json.dumps(d)


def render(size, cols, data, bare_env=False, track="shade"):
    env = {"PATH": os.environ["PATH"], "HOME": os.environ["HOME"],
           "CLAUDE_STATUSLINE_SIZE": size, "CLAUDE_STATUSLINE_TRACK": track}
    if not bare_env:
        env["LANG"] = "en_US.UTF-8"
    if cols:
        env["COLUMNS"] = str(cols)
    out = subprocess.run(["/bin/bash", script], input=data, capture_output=True,
                         text=True, env=env)
    if out.stderr:
        raise SystemExit(f"stderr: {out.stderr}")
    return out.stdout.rstrip("\n").split("\n")


from concurrent.futures import ThreadPoolExecutor
cases = [c for c in itertools.product(
        ["small", "medium"], [None, 60, 300], [200000, 1000000], ["long", "mid", "short"],
        ["both", "5h", "none"], [True, False], [False],
        [0, 45000, 95000, 105000, 120000, 210000, 999700], [0, 42, 100])
         if c[4] == "both" or c[5]]
with ThreadPoolExecutor(10) as ex:
    outs = list(ex.map(lambda c: render(c[0], c[1], payload(c[7], c[2], c[3], c[4], c[8], c[5]), c[6]), cases))

fails, checked = [], 0
# Without LANG the script must render identically (it sets LC_ALL itself).
for c in [("small", None, "long", "both"), ("medium", 60, "long", "5h")]:
    d = payload(105000, 200000, c[2], c[3], 42, True)
    if render(c[0], c[1], d) != render(c[0], c[1], d, True):
        fails.append(f"bare env differs: {c}")
    # The dots track swaps the glyph and changes nothing else.
    dots = [l.replace("⣿", "░") for l in render(c[0], c[1], d, track="dots")]
    if "⣿" not in "".join(render(c[0], c[1], d, track="dots")) or dots != render(c[0], c[1], d):
        fails.append(f"dots track differs beyond the glyph: {c}")
# The default output style is omitted; any other is shown.
d = json.loads(payload(0, 200000, "long", "none", 0, True))
for name, want in [("default", False), ("Default", False), ("Explanatory", True)]:
    d["output_style"] = {"name": name}
    if ("🎨" in render("small", None, json.dumps(d))[0]) != want:
        fails.append(f"🎨 for style {name!r} should be {'shown' if want else 'omitted'}")
# jitter: (size, cols, window, line1, bare) -> set of cell counts. Missing
# rate_limits or reset notes must not resize the bars.
groups = {}
for (size, cols, window, line1, limits, note7, bare, tokens, five), lines in zip(cases, outs):
    w0 = dw(lines[0])
    target = min(w0, cols) if cols else w0
    sig = []
    for bl in lines[1:]:
        plain = ANSI.sub("", bl)
        if "█" not in plain and "░" not in plain:
            continue
        cells = [len(m) for m in BAR.findall(plain)]
        k, n, w = len(cells), cells[0], dw(bl)
        checked += 1
        expect = max(target, w - k * n + k * 10)
        ctx = f"{size} cols={cols} win={window} l1={line1} rl={limits} n7={note7} bare={bare} tok={tokens} 5h={five}"
        if len(set(cells)) != 1:
            fails.append(f"R4 unequal {cells}: {ctx}\n  {plain}")
        if n < 10:
            fails.append(f"min cells {n}: {ctx}")
        if w != expect:
            fails.append(f"width {w} != {expect} (target {target}, W0 {w0}): {ctx}\n  {plain}")
        sig.append((k, n, w))
    if sum(k for k, _, _ in sig) != 3:
        fails.append(f"expected 3 bars, got {sig}: {size} cols={cols} l1={line1} rl={limits} n7={note7}")
    groups.setdefault((size, cols, window, line1, bare), set()).add(tuple(sig))

for key, sigs in groups.items():
    if len(sigs) > 1:
        fails.append(f"jitter {key}: {sorted(sigs)}")

print(f"{checked} bar lines checked, {len(groups)} jitter groups, {len(fails)} failures")
for f in fails[:20]:
    print("FAIL", f)

if show:
    for size, line1, limits, tokens, five, window in [
            ("small", "long", "both", 45000, 42, 200000), ("small", "mid", "both", 105000, 100, 1000000),
            ("small", "short", "5h", 0, 0, 200000), ("small", "short", "none", 210000, 0, 200000),
            ("medium", "long", "both", 120000, 42, 1000000), ("medium", "short", "5h", 95000, 42, 200000)]:
        print(f"--- {size} l1={line1} rl={limits} tok={tokens} 5h={five} win={window}")
        for l in render(size, None, payload(tokens, window, line1, limits, five, True)):
            print(l + "\x1b[0m", f"  [{dw(l)}]")
sys.exit(1 if fails else 0)
