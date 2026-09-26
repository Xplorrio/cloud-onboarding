#!/usr/bin/env python3
"""Fail on writing that the repository style rules forbid.

  * the em dash, and a double hyphen used as punctuation (" -- ")
  * filler words listed in BANNED_WORDS

Command line flags such as --stack-name, and words inside URLs, are allowed.
"""

import re
import subprocess
import sys

BANNED_WORDS = [
    "delve", "leverage", "leverages", "leveraging", "robust", "seamless", "seamlessly",
    "utilize", "utilizes", "utilizing", "foster", "tapestry", "testament", "boasts",
    "elevate", "unlock", "unleash", "dive in", "game-changer", "game changer",
    "in today's world", "it's important to note", "scaffold",
]

EM_DASH = "—"
DOUBLE_HYPHEN_RE = re.compile(r"(^|\s)--(\s|$)")
WORD_RE = re.compile(r"\b(" + "|".join(re.escape(w) for w in BANNED_WORDS) + r")\b", re.IGNORECASE)
SKIP = {"LICENSE", "scripts/check-style.py"}
URL_RE = re.compile(r"https?://\S+")


def main():
    files = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        check=True, capture_output=True,
    ).stdout.decode().split("\0")
    problems = []
    for path in filter(None, files):
        if path in SKIP:
            continue
        try:
            text = open(path, encoding="utf-8").read()
        except (UnicodeDecodeError, FileNotFoundError, IsADirectoryError):
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if EM_DASH in line:
                problems.append(f"{path}:{lineno}: em dash")
            if DOUBLE_HYPHEN_RE.search(line):
                problems.append(f"{path}:{lineno}: double hyphen used as a dash")
            for m in WORD_RE.findall(URL_RE.sub("", line)):
                problems.append(f"{path}:{lineno}: banned word '{m}'")
    if problems:
        print("Style check failed:")
        for p in problems:
            print(f"  {p}")
        return 1
    print("Style check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
