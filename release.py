#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["rich>=13.7", "pydantic>=2.6"]
# ///
"""Build a signed, notarized, universal Tokens on Track.dmg.

Notarization is submitted with --no-wait and polled, rather than handed to
`notarytool --wait`. --wait blocks silently for however long Apple takes —
typically minutes, but an hour on a Team ID with no submission history, and
there is no way to tell a slow queue from a wedged one while staring at a
blank line. Polling gives the wait an elapsed clock, a budget bar, and a line
in the log every time Apple's answer changes.

Run ./setup-signing.sh once first; this reads the .env and the keychain notary
profile it leaves behind.

    ./release.py                build dist/TokensOnTrack-<version>.dmg
    ./release.py --timeout 90   allow 90 minutes per submission
    ./release.py --publish      also tag v<version> and create a GitHub release
    ./release.py --force        rebuild even when dist/ is already current

Like make, a build is skipped when the artifacts in dist/ are newer than
everything they were built from. The compile is not what that saves — swift
build is already incremental — it is the notary queue, which took over an hour
on this team's first submission.

--publish is checked before the build, not after, so a missing gh login or a
version that was never bumped fails in the first second rather than after two
compiles and two round trips to Apple's notary queue.

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
from typing import Iterable, NoReturn, Sequence

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
# Spaces in the dmg filename survive locally but GitHub rewrites them to dots
# on download, so the artifact is named without them. The volume name keeps
# the spaces — that is what a user sees when the image is mounted.
ASSET_NAME = "TokensOnTrack"
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
def run(cmd: Sequence[str], *, capture: bool = True, timeout: float | None = None) -> str:
    """Run a command, returning stdout. Raises Fail with the tail of stderr.

    timeout matters for the polling calls: subprocess.run without one can
    block forever, and an elapsed-budget check that only runs after the call
    returns cannot interrupt it. --timeout would then be advisory.
    """
    try:
        proc = subprocess.run(
            list(cmd),
            capture_output=capture,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        fail(f"`{' '.join(cmd[:3])} ...` did not return within {timeout:.0f}s")
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
# Note this is the reverse of most dotenv libraries, and deliberately so.
# .env is the deliberate answer, written once and inspectable; an environment
# variable is usually an accident inherited from a parent shell. Signing the
# wrong artifact with the wrong certificate because something was exported
# three terminals ago is the failure worth designing against.
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
def notary_json(args: Sequence[str], profile: str, timeout: float | None = None) -> str:
    return run(
        ["xcrun", "notarytool", *args, "--keychain-profile", profile, "--output-format", "json"],
        timeout=timeout,
    )


def submit(target: Path, profile: str) -> SubmitResult:
    raw = notary_json(["submit", str(target), "--no-wait"], profile)
    try:
        return SubmitResult.model_validate_json(raw)
    except ValidationError as exc:
        fail(f"could not read notarytool's submit response:\n{raw}\n{exc}")


def poll(submission_id: str, profile: str, timeout: float | None = None) -> SubmissionStatus:
    raw = notary_json(["info", submission_id], profile, timeout=timeout)
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
        info: SubmissionStatus | None = None
        last_status = "submitted"
        transient = 0

        while True:
            elapsed = time.monotonic() - started
            progress.update(task, completed=min(elapsed, budget))

            if elapsed > budget:
                fail(
                    f"still {last_status} after {timeout_minutes} min. The submission is\n"
                    f"queued at Apple regardless — check it later with:\n"
                    f"  xcrun notarytool info {result.id} --keychain-profile {profile}"
                )

            try:
                # Bounded by what is left of the budget, so a wedged notarytool
                # cannot outlive --timeout by sitting in an unbounded read.
                info = poll(
                    result.id, profile, timeout=min(120.0, max(30.0, budget - elapsed))
                )
            except Fail as exc:
                # A blip reaching Apple is not a reason to abandon a submission
                # that is still queued. Giving up here would send the next run
                # into a second hour-long queue for a result already coming.
                transient += 1
                progress.console.print(
                    f"    [warn]poll failed ({transient}), retrying[/warn]  "
                    f"[dim]{str(exc).splitlines()[0]}[/dim]"
                )
                progress.update(task, status=f"retrying ({transient})")
                time.sleep(min(60.0, 5.0 * 2 ** min(transient, 4)))
                continue

            transient = 0
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
            time.sleep(poll_interval(elapsed))

    # The loop only leaves by break, which requires a status in hand.
    assert info is not None

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
# Is the last build still good?
#
# make's rule, without make's machinery: an output is current when it exists
# and nothing it was built from is newer. The point is not to save the compile
# — swift build is already incremental and takes under a minute — it is to
# avoid re-entering Apple's notary queue, which took over an hour on this
# team's first submission and is not something to spend twice on an unchanged
# binary.
#
# The mtime comparison alone would be too trusting, because it cannot see a
# run that died between notarizing and stapling. `stapler validate` can, so
# both have to agree before the build is skipped.
# --------------------------------------------------------------------- #
def newest_mtime(paths: Iterable[Path]) -> float:
    return max((p.stat().st_mtime for p in paths if p.exists()), default=0.0)


def source_inputs() -> list[Path]:
    """Everything that changes what the artifacts should contain.

    Directories are inputs too, not just the files in them. Deleting a source
    leaves nothing behind with a new mtime, so a files-only scan would happily
    reuse a binary that still contains the deleted code; unlinking bumps the
    parent directory instead, which is the only trace there is.

    release.py is here because it decides how the artifacts are signed, and
    .env because it can decide which certificate signs them.
    """
    roots = [Path("Sources"), Path("Resources")]
    inputs = [Path("Package.swift"), Path(__file__).resolve(), Path(".env")]
    for root in roots:
        inputs.append(root)
        inputs.extend(root.rglob("*"))
    return inputs


def signing_authority(target: Path) -> str:
    """The leaf Authority codesign reports, or "" if the target is unsigned.

    codesign -d writes its report to stderr, and returns non-zero for an
    unsigned target — neither is an error here, both are answers.
    """
    proc = subprocess.run(
        ["codesign", "-d", "--verbose=2", str(target)],
        capture_output=True,
        text=True,
    )
    for line in (proc.stderr or "").splitlines():
        if line.startswith("Authority="):
            return line.split("=", 1)[1]
    return ""


def dist_is_current(bundle: Path, dmg: Path, identity: str) -> bool:
    if not (bundle.is_dir() and dmg.is_file()):
        return False

    # min, not max: the older of the two artifacts is the one that decides
    # whether the pair as a whole predates a source edit.
    built = min(bundle.stat().st_mtime, dmg.stat().st_mtime)
    if built < newest_mtime(source_inputs()):
        return False

    # Asking the artifacts who signed them, rather than inferring it from the
    # inputs. A certificate can be renewed, revoked or swapped in the keychain
    # without any file on disk changing, and publishing yesterday's signature
    # under today's identity is not something mtimes can catch.
    if signing_authority(bundle) != identity or signing_authority(dmg) != identity:
        return False

    return quiet_ok(["xcrun", "stapler", "validate", str(bundle)]) and quiet_ok(
        ["xcrun", "stapler", "validate", str(dmg)]
    )


# --------------------------------------------------------------------- #
# Publishing
#
# gh rather than the GitHub API: the token, the auth refresh and the upload
# retries are already solved there, and the whole feature is three commands.
# --------------------------------------------------------------------- #
def git_out(args: Sequence[str]) -> str:
    return run(["git", *args]).strip()


def publish_preflight(tag: str) -> None:
    """Checked before the build, not after.

    Every one of these is a condition that would otherwise be discovered at
    the very end, having already spent two compiles and two round trips to
    Apple's notary queue.
    """
    if shutil.which("gh") is None:
        fail("gh not found. Install it with: brew install gh")

    if not quiet_ok(["gh", "auth", "status"]):
        fail("gh is not authenticated. Run: gh auth login")

    if quiet_ok(["git", "rev-parse", "--verify", "--quiet", f"refs/tags/{tag}"]):
        fail(
            f"tag {tag} already exists locally.\n"
            "Bump CFBundleShortVersionString in Resources/Info.plist, or delete\n"
            f"the tag with: git tag -d {tag}"
        )

    if git_out(["ls-remote", "--tags", "origin", tag]):
        fail(f"tag {tag} already exists on origin. Bump the version.")

    # A published binary should be reproducible from a commit someone else can
    # fetch. Dirty or unpushed means the tag would point at something that
    # does not describe what was actually built.
    if git_out(["status", "--porcelain"]):
        fail("working tree is dirty. Commit or stash before publishing.")

    if not git_out(["branch", "-r", "--contains", "HEAD"]):
        fail("HEAD is not on any remote branch. Push it before publishing.")


def publish(dmg: Path, tag: str, version: str) -> None:
    step(f"publishing {tag}")

    run(["git", "tag", "-a", tag, "-m", f"{APP_NAME} {version}"])
    run(["git", "push", "origin", tag])
    detail(f"tagged {git_out(['rev-parse', '--short', 'HEAD'])}")

    try:
        url = run(
            [
                "gh", "release", "create", tag, str(dmg),
                "--title", f"{APP_NAME} {version}",
                "--generate-notes",
            ]
        ).strip()
    except Fail:
        # The tag is already on origin at this point, and leaving it there
        # silently would make the next attempt fail the preflight above with
        # no explanation of how it got there.
        console.print(
            f"[warn]the tag is already pushed.[/warn] To retry cleanly:\n"
            f"  git push --delete origin {tag} && git tag -d {tag}"
        )
        raise

    detail(url, style="ok")


# --------------------------------------------------------------------- #
# Preflight
#
# Every check here maps to a failure that would otherwise surface minutes
# later, after a full two-architecture compile or a round trip to Apple.
# --------------------------------------------------------------------- #
def preflight(identity: str, profile: str, publishing: bool) -> tuple[str, str]:
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
    if publishing:
        table.add_row("publishing", f"v{version} to GitHub")
    console.print(Panel(table, title="release", border_style="cyan"))

    if publishing:
        publish_preflight(f"v{version}")

    return version, build


# --------------------------------------------------------------------- #
def release(timeout_minutes: int, publishing: bool, force: bool) -> None:
    os.chdir(Path(__file__).resolve().parent)

    dotenv = load_dotenv()
    identity = resolve_identity(setting("DEVELOPER_ID", dotenv))
    profile = setting("NOTARY_PROFILE", dotenv, "tokens-on-track-notary")

    version, _ = preflight(identity, profile, publishing)

    bundle = DIST_DIR / f"{APP_NAME}.app"
    dmg = DIST_DIR / f"{ASSET_NAME}-{version}.dmg"

    if not force and dist_is_current(bundle, dmg, identity):
        step("dist is up to date")
        detail("nothing newer than the last build — reusing it", style="ok")
        detail("rebuild anyway with --force")
        finish(bundle, dmg, version, publishing)
        return

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

    finish(bundle, dmg, version, publishing)


def finish(bundle: Path, dmg: Path, version: str, publishing: bool) -> None:
    """Everything that is worth doing whether or not the build just ran."""
    verify(bundle, dmg)

    if publishing:
        publish(dmg, f"v{version}", version)

    size_mb = dmg.stat().st_size / (1024 * 1024)
    console.print()
    console.print(
        Panel(
            f"[ok]{dmg}[/ok]  [dim]({size_mb:.1f} MB)[/dim]\n"
            + ("published." if publishing else "ready to upload."),
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

    # The file beats the environment, which beats the default. Worth pinning:
    # it is the reverse of what every other dotenv reader does, so it is
    # exactly the kind of thing a later "cleanup" would silently flip back.
    os.environ.pop("NOTARY_PROFILE", None)
    assert setting("NOTARY_PROFILE", parsed, "fallback") == "quoted"
    os.environ["NOTARY_PROFILE"] = "from-env"
    assert setting("NOTARY_PROFILE", parsed, "fallback") == "quoted"
    assert setting("NOTARY_PROFILE", {}, "fallback") == "from-env"
    os.environ.pop("NOTARY_PROFILE")
    assert setting("NOTARY_PROFILE", {}, "fallback") == "fallback"
    assert setting("MISSING", parsed, "fallback") == "fallback"

    assert poll_interval(0) < poll_interval(600) < poll_interval(3000)

    # The dependency rule: an artifact is current when it is newer than
    # everything it was built from. Checked on files rather than mocked, so
    # this fails if the mtime comparison is ever flipped.
    with tempfile.TemporaryDirectory() as tmp:
        older, newer = Path(tmp) / "a", Path(tmp) / "b"
        older.write_text("in", encoding="utf-8")
        os.utime(older, (1_000_000, 1_000_000))
        newer.write_text("out", encoding="utf-8")
        os.utime(newer, (2_000_000, 2_000_000))
        assert newest_mtime([older, newer]) == 2_000_000
        assert newest_mtime([older]) == 1_000_000
        assert newest_mtime([]) == 0.0
        assert newest_mtime([Path(tmp) / "missing"]) == 0.0

    # Deleting a source must register, and a directory mtime is the only
    # trace it leaves. Without this the cache happily serves a binary built
    # from code that no longer exists.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "Sources"
        root.mkdir()
        doomed = root / "Gone.swift"
        doomed.write_text("// bye", encoding="utf-8")
        os.utime(root, (1_000_000, 1_000_000))
        os.utime(doomed, (1_000_000, 1_000_000))
        before = newest_mtime([root, *root.rglob("*")])
        doomed.unlink()
        after = newest_mtime([root, *root.rglob("*")])
        assert after > before, "deleting a source must bump the directory mtime"

    # dist_is_current must refuse anything it cannot see both halves of,
    # before it ever reaches the mtime, signature or stapler checks.
    with tempfile.TemporaryDirectory() as tmp:
        missing_bundle = Path(tmp) / "nope.app"
        missing_dmg = Path(tmp) / "nope.dmg"
        assert not dist_is_current(missing_bundle, missing_dmg, "irrelevant")
        missing_bundle.mkdir()
        assert not dist_is_current(missing_bundle, missing_dmg, "irrelevant")

    # An unsigned path reports no authority, so it can never match an
    # identity — which is what keeps the signer check from passing vacuously.
    with tempfile.TemporaryDirectory() as tmp:
        unsigned = Path(tmp) / "plain.txt"
        unsigned.write_text("not signed", encoding="utf-8")
        assert signing_authority(unsigned) == ""

    inputs = source_inputs()
    assert Path(__file__).resolve() in inputs, "the script is its own input"
    assert Path(".env") in inputs, ".env can decide which certificate signs"
    assert Path("Sources") in inputs, "directories carry the deletion signal"

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
        "--publish",
        action="store_true",
        help="tag v<version> and create a GitHub release with the dmg attached",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="rebuild and re-notarize even when dist/ is already current",
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
        release(args.timeout, args.publish, args.force)
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
