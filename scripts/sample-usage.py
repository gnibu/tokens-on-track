#!/usr/bin/env python3
"""Write a sample usage.json for Store screenshots, with resets relative to now.

    python3 scripts/sample-usage.py /tmp/tot-sample
    AI_USAGE_DIR=/tmp/tot-sample AI_USAGE_FROZEN=1 <launch the direct build>
"""
import json
import os
import sys
import time

H, D = 3600, 86400
now = int(time.time())


def window(label, seconds, left, percent, **extra):
    return {"label": label, "window_seconds": seconds, "resets_at": now + left, "percent": percent, **extra}


def provider(id, kind, name, plan, windows, **extra):
    return {"id": id, "kind": kind, "name": name, "plan": plan, "ok": True, "logged_in": True,
            "stale": False, "unreachable": False, "stale_token": False, "windows": windows, **extra}


report = {
    "updated_at": now,
    "updated_label": time.strftime("%H:%M"),
    "providers": [
        provider("Claude Code-credentials", "claude", "Claude", "max", [
            window("5h", 5 * H, 2 * H, 52),
            window("week", 7 * D, 3 * D, 49),
        ], profile_path=os.path.expanduser("~/.claude")),
        provider("Codex", "codex", "Codex", "pro", [
            window("5h", 5 * H, 3 * H, 31),
            window("week", 7 * D, 5 * D, 24),
        ], profile_path=os.path.expanduser("~/.codex"), reset_credits={"available": 2, "usable_now": 0}),
        provider("OpenRouter", "openrouter", "OpenRouter", "$200/mo", [
            window("day", D, 9 * H, 51, spent_usd=3.30, budget_usd=200 / 31),
            window("month", 31 * D, 14 * D, 46, spent_usd=92.40, budget_usd=200),
        ]),
    ],
}

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "usage.json"), "w") as f:
    json.dump(report, f, indent=1)
print(os.path.join(out, "usage.json"))
