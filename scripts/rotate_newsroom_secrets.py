#!/usr/bin/env python3
"""Rotate NEWSROOM_SECRET and ADMIN_API_KEY in the local backend/.env.

Values are generated with the secrets module at runtime and written straight
into the file; they are never printed, logged, or committed. Run this once per
deployment, and again any time a credential may have leaked.

Why both:
  * ADMIN_API_KEY gates every /admin action. The shipped default is published in
    the source tree, so the newsroom refuses it entirely until it is changed.
  * NEWSROOM_SECRET signs the time-scoped admin bearer tokens. With the shipped
    value that signature is forgeable from the source alone.

Editor sessions are unaffected: they are DB-backed, not HMAC-signed with this
secret, so rotating it does not log the desk out.

Usage:
    python scripts/rotate_newsroom_secrets.py [--dry-run]
    python scripts/rotate_newsroom_secrets.py --bootstrap owner@example.news

The newsroom reads backend/.env (see README); the repository's .env.example is
the template, not a live config, so that is the file this script touches.

--bootstrap writes BOOTSTRAP_EDITOR_EMAIL/PASSWORD, which the newsroom consumes
once -- only while no account exists at all -- to create the first
administrator. It cannot be used to reset a password afterwards. The generated
password is written to backend/.env and shown nowhere else; read it there and
change it after the first sign-in.
"""

from __future__ import annotations

import argparse
import re
import secrets
import sys
from pathlib import Path

ROTATIONS = {
    "NEWSROOM_SECRET": lambda: secrets.token_urlsafe(48),
    "ADMIN_API_KEY": lambda: secrets.token_urlsafe(32),
}
BOOTSTRAP_KEYS = ("BOOTSTRAP_EDITOR_EMAIL", "BOOTSTRAP_EDITOR_PASSWORD")
PLACEHOLDER_PREFIX = "change-me"


def _substitute(text: str, key: str, value: str) -> str:
    pattern = re.compile(rf"^{key}=.*$", re.MULTILINE)
    if not pattern.search(text):
        return f"{text.rstrip()}\n{key}={value}"
    return pattern.sub(f"{key}={value}", text)


def rotate(env_path: Path, dry_run: bool) -> int:
    if not env_path.is_file():
        print(f"{env_path} not found; nothing to rotate.", file=sys.stderr)
        return 1

    text = env_path.read_text()
    updated = text
    for key, generate in ROTATIONS.items():
        updated = _substitute(updated, key, generate())

    if updated == text:
        print("No changes made.")
        return 0

    if dry_run:
        print(f"Would have rotated {len(ROTATIONS)} secrets in {env_path}.")
        return 0

    env_path.write_text(updated)
    print(f"Rotated {', '.join(ROTATIONS)} in {env_path}.")
    print("Restart the newsroom for the new values to take effect.")
    return 0


def bootstrap(env_path: Path, email: str, dry_run: bool) -> int:
    """Write the first-administrator bootstrap credentials."""
    text = env_path.read_text() if env_path.is_file() else ""
    note = (
        "\n# ---- First administrator -------------------------------------------\n"
        "# Consumed once, only while the newsroom has no accounts at all, to\n"
        "# create the first administrator. Once one exists this does nothing,\n"
        "# so it cannot be used to reset a password later.\n"
    )
    updated = text.rstrip() + note
    updated = _substitute(updated, BOOTSTRAP_KEYS[0], email.strip().lower())
    updated = _substitute(updated, BOOTSTRAP_KEYS[1], secrets.token_urlsafe(24))

    if dry_run:
        print(f"Would have written {', '.join(BOOTSTRAP_KEYS)} to {env_path}.")
        return 0

    env_path.write_text(updated + "\n")
    print(f"Wrote {', '.join(BOOTSTRAP_KEYS)} to {env_path}.")
    print("The password is in that file and nowhere else; read it and change it "
          "after the first sign-in.")
    print("Restart the newsroom for the account to be created.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env", type=Path, default=Path("backend/.env"))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--bootstrap", metavar="EMAIL",
        help="write first-administrator bootstrap credentials for this email",
    )
    args = parser.parse_args()
    if args.bootstrap:
        if "@" not in args.bootstrap:
            print("--bootstrap needs an email address", file=sys.stderr)
            return 2
        return bootstrap(args.env, args.bootstrap, args.dry_run)
    return rotate(args.env, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
