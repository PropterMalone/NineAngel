#!/usr/bin/env python3
# pattern: imperative shell (reads one binary, prints one observation, exits by contract)
"""Falsifier for ADR-21 (Haiku retired) and the CLAUDE.md "No Haiku, anywhere" rule.

the user, 2026-09-12: "if/when we get a Haiku update we'll reconsider that policy."
This makes that trigger computable. The installed Claude Code binary carries the
model-id table it can dispatch; when it learns a `claude-haiku-*` id from a newer
generation than 4.5, the premise of the rule (Haiku 4.5 is the Haiku on offer,
and it is expensive and bad) is due for a fresh look.

Contract (house:03): exit 0 = clean, 1 = fired, 2 = cannot evaluate. stdout is the
observation either way.

Usage: haiku-successor-check.py [--binary PATH]
  --binary   override the Claude Code binary to scan (tests, other installs)
"""
import argparse
import os
import re
import sys

DEFAULT_BINARY = os.path.expanduser(
    "~/.local/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
)
# Generations known on 2026-09-12: 3, 3.5, 3.55, 4, 4.5. Anything else is a successor.
KNOWN_HAIKU_GENERATIONS = {"3", "3-5", "3-55", "4", "4-5"}
HAIKU_ID_RE = re.compile(rb"claude-haiku-(\d+(?:-\d+)?)(?![0-9-])")


def successors(blob: bytes) -> list[str]:
    seen = set()
    for m in HAIKU_ID_RE.finditer(blob):
        gen = m.group(1).decode()
        if gen not in KNOWN_HAIKU_GENERATIONS:
            seen.add(m.group(0).decode())
    return sorted(seen)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--binary", default=DEFAULT_BINARY)
    args = ap.parse_args()
    try:
        with open(args.binary, "rb") as fh:
            blob = fh.read()
    except OSError as exc:
        print(f"cannot read Claude Code binary {args.binary}: {exc}")
        return 2
    found = successors(blob)
    if found:
        print("Haiku successor id(s) in installed Claude Code binary: " + ", ".join(found)
              + " — reconsider the no-Haiku rule with the user (feedback-no-haiku, ADR-21)")
        return 1
    print(f"no Haiku id newer than 4.5 in {os.path.basename(args.binary)}; rule premise holds")
    return 0


if __name__ == "__main__":
    sys.exit(main())
