"""Validate a reviewed PR draft and write its target, title, and exact body bytes."""

import re
import sys
from pathlib import Path


def refuse(check):
    sys.exit("Draft " + check + " check failed.")


try:
    draft = Path(sys.argv[1]).read_bytes()
except OSError as error:
    sys.exit("Draft file check failed: " + str(error))
lines = draft.split(b"\n")
if not sys.argv[2] or lines[0] != b"From: " + sys.argv[2].encode():
    draft_branch = (
        lines[0][len(b"From: "):].decode(errors="replace")
        if lines[0].startswith(b"From: ") else "<invalid From header>"
    )
    current_branch = sys.argv[2] or "<detached HEAD>"
    sys.exit(
        f"Draft From branch check failed: draft is for '{draft_branch}', "
        f"current branch is '{current_branch}'."
    )
target = re.fullmatch(rb"Into: ([^/\s:]+)/([^/\s:]+):([^\s:]+)", lines[1] if len(lines) > 1 else b"")
if not target:
    refuse("Into target")
if len(lines) < 3 or lines[2].strip():
    refuse("title separator")
title_index = next((i for i in range(3, len(lines)) if lines[i].strip()), None)
if title_index is None:
    refuse("title")
separator = title_index + 1
if separator >= len(lines) or lines[separator].strip():
    refuse("body separator")
body = b"\n".join(lines[separator + 1:])
if not body.strip():
    refuse("body")
root = Path(sys.argv[3])
(root / "pr-title").write_bytes(lines[title_index])
(root / "pr-repo").write_bytes(target[1] + b"/" + target[2])
(root / "pr-base").write_bytes(target[3])
(root / "pr-body.md").write_bytes(body)
