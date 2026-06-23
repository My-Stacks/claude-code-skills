"""Shared helpers for the ai-router python test suite (stdlib unittest only)."""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.normpath(os.path.join(HERE, "..", "scripts"))


def run(script, args=None, stdin=None, lib=False):
    """Run a script CLI. Returns (returncode, stdout, stderr)."""
    path = os.path.join(SCRIPTS, "lib", script) if lib else os.path.join(SCRIPTS, script)
    p = subprocess.run(
        [sys.executable, path, *(args or [])],
        input=stdin, capture_output=True, text=True,
    )
    return p.returncode, p.stdout, p.stderr
