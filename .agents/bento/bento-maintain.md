# Overlay for bento-maintain

<!-- bento:maintenance:start -->
## Discovered maintenance tools

Commands below were discovered, not executed by setup.

- **Verification** — Trigger: code-improvement, security-fix, error-fix on `Sources/`, `Tests/`, `versioning.py`. Action: `./test.sh` (Python unittest for versioning + swiftc-compiled regression tests; macOS + Command Line Tools, no secrets), `./test.sh --store` for the App Store variant, `./release.py --self-test` for release parsing. Sources: `test.sh:6-38`, `Makefile:13`, `docs/releasing.md:40`. Build check: `./build.sh` (`build.sh:5`). No lint/type checker configured.
- **Instruction ownership** — Trigger: instructions-upkeep. Action: repo skills live in `.agents/skills/` (`.claude/skills` links there); `CLAUDE.md`/`AGENTS.md` bento blocks are owned by `bento-setup`; `bento-*` skills are pinned by `skills-lock.json` and must not be hand-edited. Source: `skills-lock.json`, `.agents/skills/writing-skills/SKILL.md`.
- **Documentation** — Trigger: docs-upkeep. Action: `README.md` (user docs), `CHANGELOG.md`, `docs/*.md` (release/App Store procedures); no docs build or link checker. `Resources/Privacy.html` is published by `.github/workflows/pages.yml` — edit only that copy. Sources: `.github/workflows/pages.yml:1-3`.
- **Dependency advisories** — Trigger: security-fix. Action: no Swift package dependencies (`Package.swift` declares none); `release.py` pulls `rich`/`pydantic` via `uv` inline script metadata (`release.py:1-5`); GitHub Actions in `.github/workflows/pages.yml`. No scanner or Dependabot config; lookup via `gh api repos/gnibu/tokens-on-track/dependabot/alerts`, access unverified.
- **Error monitoring** — Trigger: error-fix. Status: unavailable (no monitoring SDK or provider declared in `Sources/`).
- **Forge and tracker** — Policy: `.agents/bento/bento-ship.md` (Ship preferences); lookup: `gh pr list` / Linear MCP (`linear-tenjin-tech`) issue search; access available in this session.
- **Protected paths** — `Config/` signing/export config, `.env`, `*.p12`/`*.p8`/provisioning files (`.gitignore`), `release.py`/`Makefile` publish targets (notarize/upload to App Store Connect — never run unattended).
<!-- bento:maintenance:end -->
