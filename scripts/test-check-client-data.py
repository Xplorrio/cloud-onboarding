#!/usr/bin/env python3
"""Tests for the commit message allowlist in check-client-data.py.

Builds throwaway git repositories, so it needs git and no key file: it sets
its own CLIENT_DATA_HMAC_KEY. Proves that an allowlisted commit message is
skipped, that any other commit message with the same finding still fails,
and that the allowlist holds exactly the one known commit.

    python3 scripts/test-check-client-data.py
"""

import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO

SCRIPT = pathlib.Path(__file__).resolve().parent / "check-client-data.py"
# Built from parts, so this file holds no address the check would flag.
FINDING = "someone" + "@" + "not-a-placeholder.io"


def load():
    os.environ["CLIENT_DATA_HMAC_KEY"] = "test-key-for-allowlist-tests"
    spec = importlib.util.spec_from_file_location("check_client_data", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(*args, cwd):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def commit(repo, message):
    path = pathlib.Path(repo) / "README.md"
    path.write_text(path.read_text() + "x\n" if path.exists() else "x\n")
    run("git", "add", "README.md", cwd=repo)
    run("git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
        "commit", "-q", "-m", message, cwd=repo)
    return run("git", "rev-parse", "HEAD", cwd=repo)


class AllowlistTest(unittest.TestCase):
    def check(self, module, repo):
        old_cwd, old_argv = os.getcwd(), sys.argv
        os.chdir(repo)
        sys.argv = ["check-client-data.py"]
        out = StringIO()
        try:
            with redirect_stdout(out):
                code = module.main()
        finally:
            os.chdir(old_cwd)
            sys.argv = old_argv
        return code, out.getvalue()

    def test_allowlisted_commit_is_skipped_and_others_still_fail(self):
        module = load()
        with tempfile.TemporaryDirectory() as repo:
            run("git", "init", "-q", cwd=repo)
            known = commit(repo, f"Known merge\n\nCo-authored-by: Owner <{FINDING}>")
            module.ALLOWED_COMMIT_MESSAGES = {known: "test"}
            code, out = self.check(module, repo)
            self.assertEqual(code, 0, out)

            new = commit(repo, f"New change\n\nCo-authored-by: Someone <{FINDING}>")
            code, out = self.check(module, repo)
            self.assertEqual(code, 1, out)
            self.assertIn(f"commit:{new[:8]}", out)
            self.assertNotIn(f"commit:{known[:8]}", out)

    def test_allowlisted_commit_files_are_still_scanned(self):
        module = load()
        with tempfile.TemporaryDirectory() as repo:
            run("git", "init", "-q", cwd=repo)
            (pathlib.Path(repo) / "notes.txt").write_text(f"contact {FINDING}\n")
            run("git", "add", "notes.txt", cwd=repo)
            known = commit(repo, "Adds a file with an address")
            module.ALLOWED_COMMIT_MESSAGES = {known: "test"}
            code, out = self.check(module, repo)
            self.assertEqual(code, 1, out)
            self.assertIn("notes.txt", out)

    def test_allowlist_is_exactly_the_known_commit(self):
        module = load()
        self.assertEqual(set(module.ALLOWED_COMMIT_MESSAGES), {"653ceb1cf3c4d55b1eafa899ce5d8e28b1d1a116"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
