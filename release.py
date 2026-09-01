#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["rich>=13.7", "pydantic>=2.6"]
# ///
"""Build a signed, notarized, universal Tokens on Track.dmg.

Same pipeline as release.sh, same artifacts, different waiting. release.sh
hands notarization to `notarytool --wait`, which blocks silently for however
long Apple takes — typically minutes, but an hour on a Team ID with no
submission history, and there is no way to tell a slow queue from a wedged one
while staring at a blank line.

This version submits with --no-wait and polls, so the wait has an elapsed
clock, a budget bar, and a line in the log every time Apple's answer changes.

Setup is identical and shared: run ./setup-signing.sh once, and this reads the
same .env and the same keychain notary profile.

    ./release.py                build dist/Tokens on Track-<version>.dmg
    ./release.py --timeout 90   allow 90 minutes per submission

Bump CFBundleShortVersionString and CFBundleVersion in Resources/Info.plist
before each release; both are read from there, so the plist stays the single
source of truth.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import NoReturn, Sequence

from pydantic import BaseModel, ConfigDict, Field, ValidationError
from rich.console import Console
from rich.panel import Panel
from rich.progress import (
    BarColumn,
    Progress,
    SpinnerColumn,
    TextColumn,
    TimeElapsedColumn,
)
from rich.table import Table
from rich.theme import Theme

APP_NAME = "Tokens on Track"
BINARY_NAME = "AIUsage"
DIST_DIR = Path("dist")
DEPLOYMENT_TARGET = "14.0"
TRIPLES = (
    f"arm64-apple-macosx{DEPLOYMENT_TARGET}",
    f"x86_64-apple-macosx{DEPLOYMENT_TARGET}",
)

console = Console(
    theme=Theme({"step": "bold cyan", "ok": "green", "warn": "yellow", "bad": "bold red"})
)


# --------------------------------------------------------------------- #
# Apple's JSON, validated rather than trusted
#
# notarytool's shape is stable but undocumented, and a silently missing
# `status` would otherwise read as "not Accepted" and abort a good release —
# or worse, an unexpected shape would read as success. Parsing through a model
# turns that into a loud error at the point it happens.
# --------------------------------------------------------------------- #
class SubmitResult(BaseModel):
    model_config = ConfigDict(extra="ignore")

    id: str
    message: str = ""


class SubmissionStatus(BaseModel):
    model_config = ConfigDict(extra="ignore", populate_by_name=True)

    id: str
    status: str
    name: str = ""
    created_date: str = Field("", alias="createdDate")

    @property
    def finished(self) -> bool:
        return self.status not in {"In Progress", "Uploaded"}

    @property
    def accepted(self) -> bool:
        return self.status == "Accepted"


class Fail(Exception):
    """Anything that should stop the release with a readable message."""


def fail(message: str) -> NoReturn:
    raise Fail(message)


# --------------------------------------------------------------------- #
# Process helpers
# --------------------------------------------------------------------- #
def run(cmd: Sequence[str], *, capture: bool = True) -> str:
    """Run a command, returning stdout. Raises Fail with the tail of stderr."""
    proc = subprocess.run(
        list(cmd),
        capture_output=capture,
        text=True,
    )
    if proc.returncode != 0:
        detail = ((proc.stderr or "") + (proc.stdout or "")).strip() if capture else ""
        tail = "\n".join(detail.splitlines()[-25:])
        fail(f"`{' '.join(cmd[:3])} ...` exited {proc.returncode}\n{tail}")
    return proc.stdout or ""


def quiet_ok(cmd: Sequence[str]) -> bool:
    """True when the command succeeds. For probes, where failure is an answer."""
    return (
        subprocess.run(
            list(cmd), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode
        == 0
    )


def step(text: str) -> None:
    console.print(f"[step]==>[/step] {text}")


def detail(text: str, style: str = "dim") -> None:
    console.print(f"    [{style}]{text}[/{style}]")


# --------------------------------------------------------------------- #
# Configuration
#
# Resolution order: .env, then the environment, then auto-detection.
#
# Note this is the reverse of most dotenv libraries, and deliberately so — it
# matches `. ./.env` in release.sh, where a plain assignment in the file
# overwrites whatever was exported. Two release scripts that read the same
# file and disagree about which value wins is a worse trap than either rule on
# its own. .env is the checked-in-shaped, deliberate answer; the environment
# is the accident.
# --------------------------------------------------------------------- #
def load_dotenv(path: Path = Path(".env")) -> dict[str, str]:
    if not path.is_file():
        return {}
    values: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, raw = line.partition("=")
        values[key.strip()] = raw.strip().strip('"').strip("'")
    return values


def setting(name: str, dotenv: dict[str, str], default: str = "") -> str:
    return dotenv.get(name) or os.environ.get(name) or default


def find_signing_identities() -> list[str]:
    out = run(["security", "find-identity", "-v", "-p", "codesigning"])
    found: list[str] = []
    for line in out.splitlines():
        if '"Developer ID Application:' not in line:
            continue
        found.append(line.split('"')[1])
    return found


def resolve_identity(configured: str) -> str:
    """One certificate is the answer; two is a decision only the user can make."""
    identities = find_signing_identities()
    if configured:
        if configured not in identities:
            fail(
                f'no codesigning identity matching "{configured}" in the keychain.\n'
                "Run: security find-identity -v -p codesigning"
            )
        return configured
    if not identities:
        fail(
            'no "Developer ID Application" certificate in the keychain.\n'
            "Run: ./setup-signing.sh"
        )
    if len(identities) > 1:
        listing = "\n".join(f"  {i}" for i in identities)
        fail(
            f'more than one "Developer ID Application" certificate:\n{listing}\n'
            "Choose one in .env — see .env.example."
        )
    return identities[0]


# --------------------------------------------------------------------- #
# Notarization
#
# --no-wait plus a poll loop, rather than --wait. Same submission, same
# result; the difference is that a 40-minute queue looks like a 40-minute
# queue instead of a hung terminal.
# --------------------------------------------------------------------- #
def notary_json(args: Sequence[str], profile: str) -> str:
    return run(
        ["xcrun", "notarytool", *args, "--keychain-profile", profile, "--output-format", "json"]
    )


def submit(target: Path, profile: str) -> SubmitResult:
    raw = notary_json(["submit", str(target), "--no-wait"], profile)
    try:
        return SubmitResult.model_validate_json(raw)
    except ValidationError as exc:
        fail(f"could not read notarytool's submit response:\n{raw}\n{exc}")


def poll(submission_id: str, profile: str) -> SubmissionStatus:
    raw = notary_json(["info", submission_id], profile)
    try:
        return SubmissionStatus.model_validate_json(raw)
    except ValidationError as exc:
        fail(f"could not read notarytool's info response:\n{raw}\n{exc}")


def poll_interval(elapsed: float) -> int:
    """Attentive early, unhurried later. Apple rarely answers in the first minute."""
    if elapsed < 120:
        return 10
    if elapsed < 900:
        return 20
    return 30


def notarize(target: Path, label: str, profile: str, timeout_minutes: int) -> None:
    step(f"notarizing {label}")
    result = submit(target, profile)
    detail(f"submission {result.id}")

    budget = timeout_minutes * 60
    started = time.monotonic()
    last_status = ""

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(bar_width=30),
        TextColumn("{task.fields[status]}"),
        TimeElapsedColumn(),
        console=console,
        transient=True,
    ) as progress:
        task = progress.add_task(
            f"waiting on Apple ({label})", total=budget, status="submitted"
        )
        while True:
            elapsed = time.monotonic() - started
            progress.update(task, completed=min(elapsed, budget))

            info = poll(result.id, profile)
            if info.status != last_status:
                stamp = time.strftime("%H:%M:%S")
                progress.console.print(
                    f"    [dim]{stamp}[/dim]  {info.status}  "
                    f"[dim]({elapsed / 60:.1f} min elapsed)[/dim]"
                )
                last_status = info.status
            progress.update(task, status=info.status)

            if info.finished:
                break
            if elapsed > budget:
                fail(
                    f"still {info.status} after {timeout_minutes} min. The submission is\n"
                    f"queued at Apple regardless — check it later with:\n"
                    f"  xcrun notarytool info {result.id} --keychain-profile {profile}"
                )
            time.sleep(poll_interval(elapsed))

    if not info.accepted:
        log = run(
            ["xcrun", "notarytool", "log", result.id, "--keychain-profile", profile]
        )
        console.print(Panel(log.strip() or "(no log returned)", title="notary log", style="bad"))
        fail(f"notarization of {label} came back {info.status}")

    detail(f"accepted after {(time.monotonic() - started) / 60:.1f} min", style="ok")


# --------------------------------------------------------------------- #
# Build
# --------------------------------------------------------------------- #
def compile_universal(work: Path) -> Path:
    """swift build cannot emit a universal binary without xcbuild, so lipo does it."""
    step("compiling universal binary")
    slices: list[str] = []
    for triple in TRIPLES:
        with console.status(f"    [dim]{triple}[/dim]", spinner="dots"):
            run(["swift", "build", "-c", "release", "--triple", triple])
            bin_path = run(
                ["swift", "build", "-c", "release", "--triple", triple, "--show-bin-path"]
            ).strip()
        detail(f"{triple} ok", style="ok")
        slices.append(str(Path(bin_path) / BINARY_NAME))

    fused = work / BINARY_NAME
    run(["lipo", "-create", "-output", str(fused), *slices])
    detail(run(["lipo", "-info", str(fused)]).strip())
    return fused


def assemble(bundle: Path, binary: Path) -> None:
    step(f"assembling {bundle}")
    macos = bundle / "Contents" / "MacOS"
    resources = bundle / "Contents" / "Resources"
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)

    shutil.copy2(binary, macos / BINARY_NAME)
    shutil.copy2("Resources/Info.plist", bundle / "Contents" / "Info.plist")
    shutil.copy2("Resources/AppIcon.icns", resources / "AppIcon.icns")
    shutil.copytree("Resources/Icons", resources / "Icons")
    (bundle / "Contents" / "PkgInfo").write_text("APPL????", encoding="ascii")


def sign(target: Path, identity: str, *, hardened: bool) -> None:
    """--options runtime is what notarization requires; --timestamp is mandatory.

    No entitlements: the app reads the Claude keychain item by spawning
    /usr/bin/security, and the hardened runtime only restricts what loads into
    this process, not what it exec's. ~/.codex/auth.json is a plain read from
    an unsandboxed process. Entitlements here would be cargo cult.
    """
    options = ["--options", "runtime"] if hardened else []
    run(["codesign", "--force", *options, "--timestamp", "--sign", identity, str(target)])


def build_dmg(bundle: Path, dmg: Path, version: str, work: Path) -> None:
    step(f"building {dmg}")
    root = work / "dmg"
    root.mkdir()
    shutil.copytree(bundle, root / bundle.name, symlinks=True)
    (root / "Applications").symlink_to("/Applications")

    run(
        [
            "hdiutil", "create",
            "-volname", f"{APP_NAME} {version}",
            "-srcfolder", str(root),
            "-fs", "HFS+", "-format", "UDZO", "-ov",
            str(dmg),
        ]
    )


def verify(bundle: Path, dmg: Path) -> None:
    """codesign --verify only proves the signature is intact.

    spctl is what actually answers "will this open on a Mac that has never
    seen it", so it runs last and against the stapled artifacts.
    """
    step("verifying")
    run(["spctl", "--assess", "--type", "exec", "--verbose=4", str(bundle)])
    run(
        [
            "spctl", "--assess", "--type", "open",
            "--context", "context:primary-signature",
            "--verbose=4", str(dmg),
        ]
    )
    run(["xcrun", "stapler", "validate", str(bundle)])
    run(["xcrun", "stapler", "validate", str(dmg)])
    detail("Gatekeeper accepts both artifacts", style="ok")


# --------------------------------------------------------------------- #
# Preflight
#
# Every check here maps to a failure that would otherwise surface minutes
# later, after a full two-architecture compile or a round trip to Apple.
# --------------------------------------------------------------------- #
def preflight(identity: str, profile: str) -> tuple[str, str]:
    step("preflight")

    if not identity.startswith("Developer ID Application:"):
        fail(
            'DEVELOPER_ID must be a "Developer ID Application: ..." identity.\n'
            "An Apple Development or 3rd Party Mac Developer certificate will\n"
            "sign fine and then fail notarization."
        )

    if not quiet_ok(["xcrun", "--find", "notarytool"]):
        fail("notarytool not found. Install the Command Line Tools.")

    if not quiet_ok(["xcrun", "notarytool", "history", "--keychain-profile", profile]):
        fail(f'notary profile "{profile}" is missing or invalid.\nRun: ./setup-signing.sh')

    with open("Resources/Info.plist", "rb") as handle:
        info = plistlib.load(handle)
    version = str(info["CFBundleShortVersionString"])
    build = str(info["CFBundleVersion"])

    table = Table.grid(padding=(0, 2))
    table.add_column(style="dim")
    table.add_column()
    table.add_row("app", f"{APP_NAME} {version} ({build})")
    table.add_row("identity", identity)
    table.add_row("notary profile", profile)
    console.print(Panel(table, title="release", border_style="cyan"))

    return version, build


# --------------------------------------------------------------------- #
def release(timeout_minutes: int) -> None:
    os.chdir(Path(__file__).resolve().parent)

    dotenv = load_dotenv()
    identity = resolve_identity(setting("DEVELOPER_ID", dotenv))
    profile = setting("NOTARY_PROFILE", dotenv, "tokens-on-track-notary")

    version, _ = preflight(identity, profile)

    bundle = DIST_DIR / f"{APP_NAME}.app"
    dmg = DIST_DIR / f"{APP_NAME}-{version}.dmg"

    if DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    DIST_DIR.mkdir()

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)

        binary = compile_universal(work)
        assemble(bundle, binary)

        step("signing app")
        sign(bundle, identity, hardened=True)
        run(["codesign", "--verify", "--strict", "--verbose=2", str(bundle)])

        # Two submissions: the app, then the finished disk image. Stapling both
        # means the app still validates offline if a user drags it out of the
        # .dmg, and the .dmg opens cleanly on a machine that has never seen it.
        zipped = work / "app.zip"
        run(["ditto", "-c", "-k", "--keepParent", str(bundle), str(zipped)])
        notarize(zipped, "app", profile, timeout_minutes)

        step("stapling app")
        run(["xcrun", "stapler", "staple", str(bundle)])

        build_dmg(bundle, dmg, version, work)

        step("signing dmg")
        sign(dmg, identity, hardened=False)

        notarize(dmg, "dmg", profile, timeout_minutes)

        step("stapling dmg")
        run(["xcrun", "stapler", "staple", str(dmg)])

        verify(bundle, dmg)

    size_mb = dmg.stat().st_size / (1024 * 1024)
    console.print()
    console.print(
        Panel(
            f"[ok]{dmg}[/ok]  [dim]({size_mb:.1f} MB)[/dim]\nready to upload.",
            border_style="green",
        )
    )


# --------------------------------------------------------------------- #
# Self-test
#
# The parts worth a check are the ones that read someone else's output —
# Apple's JSON and the user's .env — plus the identity rule, where being wrong
# means signing a public release with the wrong certificate. Everything else
# is a subprocess call that fails loudly on its own.
# --------------------------------------------------------------------- #
def self_test() -> int:
    submitted = SubmitResult.model_validate_json(
        '{"id": "abc-123", "message": "Successfully uploaded file", "path": "/tmp/app.zip"}'
    )
    assert submitted.id == "abc-123", submitted

    in_progress = SubmissionStatus.model_validate_json(
        '{"createdDate": "2026-09-01T13:14:06.981Z", "id": "f109", '
        '"name": "app.zip", "status": "In Progress"}'
    )
    assert not in_progress.finished and not in_progress.accepted, in_progress
    assert in_progress.created_date.startswith("2026-"), in_progress

    accepted = SubmissionStatus.model_validate_json('{"id": "f109", "status": "Accepted"}')
    assert accepted.finished and accepted.accepted, accepted

    invalid = SubmissionStatus.model_validate_json('{"id": "f109", "status": "Invalid"}')
    assert invalid.finished and not invalid.accepted, invalid

    try:
        SubmissionStatus.model_validate_json('{"id": "f109"}')
    except ValidationError:
        pass
    else:  # a missing status must not silently read as "not accepted"
        raise AssertionError("missing status should not validate")

    with tempfile.TemporaryDirectory() as tmp:
        env_file = Path(tmp) / ".env"
        env_file.write_text(
            '# comment\n\nDEVELOPER_ID="Developer ID Application: X (T1)"\n'
            "APPLE_ID=you@example.com\nNOTARY_PROFILE='quoted'\n",
            encoding="utf-8",
        )
        parsed = load_dotenv(env_file)
    assert parsed["DEVELOPER_ID"] == "Developer ID Application: X (T1)", parsed
    assert parsed["APPLE_ID"] == "you@example.com", parsed
    assert parsed["NOTARY_PROFILE"] == "quoted", parsed

    # The file beats the environment, which beats the default — the same way
    # round as `. ./.env` in release.sh. Worth pinning: it is the reverse of
    # what every other dotenv reader does, so it is exactly the kind of thing
    # a later "cleanup" would silently flip back.
    os.environ.pop("NOTARY_PROFILE", None)
    assert setting("NOTARY_PROFILE", parsed, "fallback") == "quoted"
    os.environ["NOTARY_PROFILE"] = "from-env"
    assert setting("NOTARY_PROFILE", parsed, "fallback") == "quoted"
    assert setting("NOTARY_PROFILE", {}, "fallback") == "from-env"
    os.environ.pop("NOTARY_PROFILE")
    assert setting("NOTARY_PROFILE", {}, "fallback") == "fallback"
    assert setting("MISSING", parsed, "fallback") == "fallback"

    assert poll_interval(0) < poll_interval(600) < poll_interval(3000)

    one = "Developer ID Application: One (AAAAAAAAAA)"
    two = "Developer ID Application: Two (BBBBBBBBBB)"
    real = globals()["find_signing_identities"]
    try:
        globals()["find_signing_identities"] = lambda: [one]
        assert resolve_identity("") == one
        globals()["find_signing_identities"] = lambda: [one, two]
        for configured, expected_in_message in (("", "more than one"), ("nope", "no codesigning")):
            try:
                resolve_identity(configured)
            except Fail as exc:
                assert expected_in_message in str(exc), exc
            else:
                raise AssertionError(f"resolve_identity({configured!r}) should have failed")
        assert resolve_identity(two) == two
        globals()["find_signing_identities"] = list
        try:
            resolve_identity("")
        except Fail as exc:
            assert "setup-signing.sh" in str(exc), exc
        else:
            raise AssertionError("no certificate should have failed")
    finally:
        globals()["find_signing_identities"] = real

    console.print("[ok]self-test passed[/ok]")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=f"Release {APP_NAME}.")
    parser.add_argument(
        "--timeout",
        type=int,
        default=60,
        metavar="MINUTES",
        help="how long to wait on each notarization before giving up (default: 60)",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="check the parsing and identity logic, build nothing",
    )
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    try:
        release(args.timeout)
    except Fail as exc:
        console.print(f"[bad]error:[/bad] {exc}")
        return 1
    except KeyboardInterrupt:
        # Ctrl-C during the poll loop does not cancel anything at Apple's end;
        # say so, because the natural assumption is the opposite.
        console.print("\n[warn]interrupted.[/warn] Any submission already sent is still")
        console.print("queued at Apple — check with: xcrun notarytool history")
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
