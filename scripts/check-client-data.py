#!/usr/bin/env python3
"""Fail if the repository holds anything that looks like real customer data.

This repository is meant to be public, so every example must use placeholders.
The check reads every tracked or staged file, every blob in the git history
and every commit message, and fails on:

  * a 12 digit number that is not a placeholder or Xplorr's own AWS account id
  * a GUID that is not a placeholder or a published Azure built-in role id
  * an email address outside the reserved example domains
  * a Google Cloud billing account id that is not a placeholder
  * a known customer or account name

The customer names are stored only as HMAC-SHA256 values of their lowercased
letters and digits, keyed with a secret that is not in the repository, so
neither the names nor guessable hashes of them are here. The key comes from
the CLIENT_DATA_HMAC_KEY environment variable (a repository Actions secret in
CI). Without it the name check fails rather than passing silently.

To add a name, with the key exported, run:

    python3 scripts/check-client-data.py --hash "Some Name"

and paste the printed line into FORBIDDEN_NAME_HMACS.

Usage:
    python3 scripts/check-client-data.py            # working tree and history
    python3 scripts/check-client-data.py --no-history
"""

import argparse
import hashlib
import hmac
import os
import re
import subprocess
import sys

# The only real 12 digit id allowed. Placeholders made of one repeated digit,
# such as 111111111111, are allowed by pattern. Everything else fails.
ALLOWED_ACCOUNT_IDS = {
    "732121667940",  # Xplorr's own AWS account, the principal for keyless onboarding
}

# GUIDs that are allowed. Placeholders made of one repeated hex digit are
# allowed by pattern; the rest are published Azure built-in role definition
# ids (learn.microsoft.com/azure/role-based-access-control/built-in-roles),
# which are the same in every tenant.
ALLOWED_GUIDS = {
    "acdd72a7-3385-48ef-bd42-f606fba81ae7",  # Reader
    "72fafb9e-0641-4937-9268-a91bfd8191a3",  # Cost Management Reader
    "43d0d8ad-25c7-4714-9337-8ba259a9fe05",  # Monitoring Reader
    "fa0d39e6-28e5-40cf-8521-1eb320653a4c",  # Carbon Optimization Reader
    "582fc458-8989-419f-a480-75249bc5db7e",  # Reservations Reader
    "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1",  # Storage Blob Data Reader
}

ALLOWED_EMAIL_DOMAINS = ("example.com", "example.org", "example.net")
ALLOWED_EMAILS = {"git@github.com", "security@xplorr.io"}  # security@ is the published reporting address

# (HMAC-SHA256 of the normalized name, its length, how it is matched)
#   word: the name must be a whole token, or 2 to 4 adjacent tokens joined
#   sub:  the name may appear anywhere once separators are removed
FORBIDDEN_NAME_HMACS = [
    ("d36b7c6f243ac91a624c5256ce05bb3649d13002fefb5a469e46a294d60bbc39", 5, "word"),
    ("3012717ce9d30e8498b21645702ea1c74c824e9610472652e2c6bffdd53aafbb", 5, "word"),
    ("fa65fa57d2483c3c5ecba2be4bdcdd3de01589021ead4134b2df2ea46d2ec83e", 7, "word"),
    ("8d2c1c5db95ea9dd10d8e1172ffcb5da3a2f3ebb1367e4661709487c0ba51ec6", 7, "word"),
    ("9df076da37d12ea803b3bcb3fc847f6720e7fafca48c16a2a2af1f00b93f50bc", 12, "word"),
    ("3f579d2e2ce268819b95a88b7aea1a14bb0e622a8962274253cc91928f0ac298", 6, "sub"),
    ("02b1cf56c11e1a2f8cf9a39abded8940d1d9945d349660f8d4f26ce95ed645c2", 9, "sub"),
    ("499856edade4c860850fcb7654617fa86185d3d5943423109bb60df830c5911f", 10, "sub"),
    ("968095fc95cc5d76e2c49f3b900ad1f2ba3b5e77f12d3a01b17cf758cf30e193", 29, "sub"),
    ("69150c2de5cb0a2b43985c9295c62458ed57843f967200affc9e7be825f1d482", 23, "sub"),
    ("bf473aa0ec2f1cd9991a22a25ba652710d88c11a1ec8d13ac26f6ae73f1d3125", 17, "sub"),
    ("44eb509515a02fefeba527384633442ab0eae9fab4802d017c8070d11199d145", 10, "sub"),
    ("99f3043da7ac9a8d0f313e7ab95af86c40b3c8faa4bba0fdcbe709ca1f547d65", 7, "sub"),
    ("1741049322c26294db30cf3bd99af433b3048369784ee03bff79a39e7712f67a", 6, "sub"),
    ("f0c3e0a01c94b1aaedd6de9eb447d37c5986ac19543cd8a28f3b48acff8413ac", 12, "sub"),
    ("0afc9bd610b6c39e4c9294cf619883c86184d989be65f915e87b75900b0a64d9", 14, "sub"),
    ("3dc13c4878ad26b29403c7b5fb4f438d63a9b7c9619901cfc90cc6b84ccd6531", 8, "sub"),
    ("d4e02a10eedf84b5151fea92f319fc9957b40910b467f472e47770a0e822ed28", 12, "sub"),
]

ACCOUNT_ID_RE = re.compile(r"(?<![0-9A-Za-z])[0-9]{12}(?![0-9A-Za-z])")
GUID_RE = re.compile(r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}(?![0-9A-Fa-f])")
EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")
BILLING_ACCOUNT_RE = re.compile(r"(?<![0-9A-Za-z])[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}(?![0-9A-Za-z])")
TOKEN_RE = re.compile(r"[a-z0-9]+")


KEY_ENV = "CLIENT_DATA_HMAC_KEY"
HMAC_KEY = os.environ.get(KEY_ENV, "").strip().encode()


def sha(text):
    return hmac.new(HMAC_KEY, text.encode(), hashlib.sha256).hexdigest()


WORD_HASHES = {h for h, _, mode in FORBIDDEN_NAME_HMACS if mode == "word"}
SUB_HASHES = {h for h, _, mode in FORBIDDEN_NAME_HMACS if mode == "sub"}
SUB_LENGTHS = sorted({n for _, n, mode in FORBIDDEN_NAME_HMACS if mode == "sub"})


def placeholder_guid(guid):
    return len(set(guid.replace("-", "").lower())) == 1


def email_allowed(email):
    email = email.lower()
    if email in ALLOWED_EMAILS:
        return True
    domain = email.split("@", 1)[1]
    if any(domain == d or domain.endswith("." + d) for d in ALLOWED_EMAIL_DOMAINS):
        return True
    # A service account address in a placeholder project, for example
    # xplorr-reader@my-project.iam.gserviceaccount.com
    if domain.endswith(".iam.gserviceaccount.com"):
        project = domain[: -len(".iam.gserviceaccount.com")]
        return project in {"my-project", "my-project-id", "your-project-id", "example-project", "xplorr-example"}
    return False


def find_names(text):
    lowered = text.lower()
    tokens = TOKEN_RE.findall(lowered)
    for n in range(1, 5):
        for i in range(len(tokens) - n + 1):
            if sha("".join(tokens[i:i + n])) in WORD_HASHES:
                return True
    stream = "".join(tokens)
    for length in SUB_LENGTHS:
        for i in range(len(stream) - length + 1):
            if sha(stream[i:i + length]) in SUB_HASHES:
                return True
    return False


def scan(label, text):
    problems = []
    for lineno, line in enumerate(text.splitlines(), 1):
        where = f"{label}:{lineno}"
        for m in ACCOUNT_ID_RE.findall(line):
            if m not in ALLOWED_ACCOUNT_IDS and len(set(m)) != 1:
                problems.append(f"{where}: 12 digit number {m} looks like a real AWS account id")
        for m in GUID_RE.findall(line):
            if m.lower() not in ALLOWED_GUIDS and not placeholder_guid(m):
                problems.append(f"{where}: GUID {m} looks like a real tenant, subscription or client id")
        for m in EMAIL_RE.findall(line):
            if not email_allowed(m):
                problems.append(f"{where}: email address {m} is not a placeholder")
        for m in BILLING_ACCOUNT_RE.findall(line):
            if len(set(m.replace("-", ""))) != 1:
                problems.append(f"{where}: {m} looks like a real Google Cloud billing account id")
    if find_names(text):
        problems.append(f"{label}: contains a customer or account name from the forbidden list")
    return problems


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True).stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-history", action="store_true", help="scan only the working tree")
    parser.add_argument("--hash", metavar="NAME", help="print the entry for a new forbidden name and exit")
    args = parser.parse_args()

    if not HMAC_KEY:
        print(
            f"Client data check cannot run: {KEY_ENV} is not set, so the customer name "
            "check would pass without checking anything.\n"
            f"Export it first, for example: export {KEY_ENV}=\"$(cat <path to the key file>)\"\n"
            "In CI it comes from the repository secret of the same name."
        )
        return 2

    if args.hash:
        normalized = "".join(TOKEN_RE.findall(args.hash.lower()))
        mode = "word" if len(normalized) < 6 else "sub"
        print(f'    ("{sha(normalized)}", {len(normalized)}, "{mode}"),')
        return 0

    problems = []
    seen = set()

    files = git("ls-files", "-z", "--cached", "--others", "--exclude-standard").decode().split("\0")
    for path in filter(None, files):
        try:
            with open(path, "rb") as fh:
                data = fh.read()
        except (FileNotFoundError, IsADirectoryError):
            continue
        seen.add(hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest())
        problems += scan(path, data.decode("utf-8", errors="replace"))

    if not args.no_history:
        has_commits = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], capture_output=True).returncode == 0
        if has_commits:
            for line in git("rev-list", "--all", "--objects").decode().splitlines():
                parts = line.split(" ", 1)
                oid = parts[0]
                if oid in seen:
                    continue
                if git("cat-file", "-t", oid).strip() != b"blob":
                    continue
                seen.add(oid)
                name = parts[1] if len(parts) > 1 else oid
                problems += scan(f"history:{name}@{oid[:8]}", git("cat-file", "-p", oid).decode("utf-8", errors="replace"))
            for commit in git("rev-list", "--all").decode().split():
                problems += scan(f"commit:{commit[:8]}", git("log", "-1", "--format=%B", commit).decode())

    if problems:
        print("Client data check failed:")
        for p in problems:
            print(f"  {p}")
        return 1
    print(f"Client data check passed ({len(seen)} blobs scanned)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
