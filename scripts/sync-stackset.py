#!/usr/bin/env python3
"""Embed aws/cloudformation/role.yaml into stackset.yaml as the StackSet TemplateBody.

role.yaml is the one definition of the Xplorr role. stackset.yaml carries a
copy of it between the BEGIN and END markers, because a StackSet resource
takes its template inline or from S3.

    python3 scripts/sync-stackset.py          # rewrite stackset.yaml
    python3 scripts/sync-stackset.py --check  # fail if it is out of date
"""

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ROLE = ROOT / "aws/cloudformation/role.yaml"
STACKSET = ROOT / "aws/cloudformation/stackset.yaml"
BEGIN = "      # BEGIN role.yaml"
END = "      # END role.yaml"
INDENT = " " * 8


def render():
    text = STACKSET.read_text()
    head, rest = text.split(BEGIN, 1)
    begin_line, rest = rest.split("\n", 1)
    _, tail = rest.split(END, 1)
    body = "".join(
        (INDENT + line if line.strip() else "") + "\n"
        for line in ROLE.read_text().splitlines()
    )
    return f"{head}{BEGIN}{begin_line}\n      TemplateBody: |\n{body}{END}{tail}"


def main():
    new = render()
    if "--check" in sys.argv:
        if STACKSET.read_text() != new:
            print("stackset.yaml is out of date with role.yaml. Run: python3 scripts/sync-stackset.py")
            return 1
        print("stackset.yaml matches role.yaml")
        return 0
    STACKSET.write_text(new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
