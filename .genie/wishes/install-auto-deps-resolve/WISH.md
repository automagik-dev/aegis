# Wish: Installer Auto-Resolve Missing Dependencies (cosign, slsa-verifier)

| Field | Value |
|-------|-------|
| **Status** | DRAFT |
| **Slug** | `install-auto-deps-resolve` |
| **Date** | 2026-04-24 |
| **Author** | Felipe + Genie (post-v0.1.0 field-test feedback) |
| **Appetite** | small (~4h) |
| **Branch** | `fix/install-auto-deps-resolve` |
| **Repos touched** | `automagik-dev/aegis` |
| **Design** | _No brainstorm — direct wish_ |
| **Closes** | [automagik-dev/aegis#5](https://github.com/automagik-dev/aegis/issues/5) |

## Summary

The v0.1.0 installer refuses to run if `cosign` is missing from PATH, even on macOS where one `brew install cosign` would solve it. On Felipe's field-test (darwin/arm64, 2026-04-24) this broke the one-liner install experience — the user had to manually install the security dependency, then re-pipe the installer. That friction undermines the "2050 AV feel" we committed to. This wish makes the installer detect the host's package manager, offer to install the missing dependency with explicit user consent, and install it in-band so the one-liner `curl | bash` actually works first-time on a fresh macOS / Debian / Fedora / Arch box.

## Preconditions

- ✅ v0.1.0 shipped end-to-end (cosign + SLSA + GitHub Release + GHP publish all verified). This wish improves the install UX without touching the trust chain itself.
- ✅ Issue [automagik-dev/aegis#5](https://github.com/automagik-dev/aegis/issues/5) describes the problem + proposed behavior.

## Scope

### IN

**Package-manager detection** in `install.sh`:
- macOS: detect Homebrew (`command -v brew`)
- Linux apt-based (Debian/Ubuntu): detect `apt-get`
- Linux rpm-based (Fedora/RHEL/AlmaLinux/Rocky): detect `dnf` (fall back to `yum`)
- Linux Arch/Manjaro: detect `pacman`
- Linux Alpine: detect `apk`
- Nix: detect `nix-env` / `nix profile`

**Auto-install offer** when `cosign` (or `slsa-verifier` if the user wants the full 3-layer check) is missing:
1. Detect package manager per above.
2. If detected: print the exact command that would run + an interactive `[Y/n]` prompt.
3. If user accepts: `exec` the install command. Fail loudly with the underlying error if it errors.
4. Re-test `command -v cosign` after install; fall through to normal verification.
5. If no supported package manager detected: print current-behavior error (manual install URL + `--skip-verify`).

**Non-interactive flags** for automation:
- `--auto-install-deps` — assume "yes" on dep-install prompts (for Dockerfiles, CI pipelines).
- `--no-install-deps` — explicitly refuse to install anything; print manual instructions and exit.

**slsa-verifier:** currently a warning when missing. Upgrade the offer to match cosign's auto-install treatment (same detection + prompt + install), but keep it OPTIONAL — no prompt if `cosign` alone is enough for the user's threat model. Detection and offer, not forced install.

**Linux sudo handling:** `apt-get install` / `dnf install` require sudo. Detect whether the caller is root; if not, prefix with `sudo -E` and warn clearly: "Will run: `sudo -E apt-get install -y cosign`. Requires sudo credentials. [Y/n]". Never silently `sudo`.

**Documentation:**
- README "Install" section updated to show the new one-liner flow (cosign installs in-band on macOS/Linux with pkg manager).
- `docs/install/troubleshooting.md` (new) covers: no pkg manager detected, sudo denied, cosign install failure, offline/air-gapped machines.

### OUT

- Installing `aegis` on Windows (PowerShell installer is a future wish — this one is POSIX only).
- Auto-installing `bun` or `node` if missing. Those are language-runtime dependencies; users choose their version. The installer detects and errors with the minimum-version guidance it already does.
- Bundling cosign binaries inside `@automagik-dev/aegis` (supply-chain expansion risk — keep cosign installed from its own signed source).
- Changing the trust-chain verification logic itself. This wish is install UX only.
- Adding a GUI / TUI installer. POSIX shell only.

## Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Interactive prompt with explicit consent, never silent sudo | A security tool that silently elevates breaks its own trust model; explicit consent is a one-keystroke cost for big safety gain. |
| 2 | `--auto-install-deps` flag for automation instead of default-yes | CI + Dockerfiles get a clean non-interactive path; humans never get surprised by `sudo apt install` running without them hitting Enter. |
| 3 | `slsa-verifier` stays optional; only offer auto-install, never require it | Threat-model choice: cosign covers signature integrity; SLSA provenance is additional but not strictly required for identity pinning. Keeping it optional honors minimum-friction. |
| 4 | Do NOT bundle cosign binaries | Supply-chain expansion: every binary we bundle widens our surface. cosign should come from Sigstore's own signed release channel. |
| 5 | Linux support across apt / dnf / pacman / apk / nix — not just apt | Namastex ships to a diverse Linux audience; single-distro support would break the one-liner promise on ~60% of hosts. |
| 6 | Windows out of scope for this wish | PowerShell installer is a different script with different conventions; overloading POSIX install.sh with PowerShell branching makes it unmaintainable. |
| 7 | When no pkg manager is detected, keep current `✗ cosign not on PATH...` message | Manual-install path for air-gapped hosts, custom distros, and systems without sudo. Preserves the operator's agency. |

## Success Criteria

- [ ] `curl -fsSL .../install.sh | bash` on a fresh macOS (Apple Silicon + Intel) without cosign: installer detects brew → prompts `brew install cosign? [Y/n]` → user hits Enter → cosign installs → aegis installs → `aegis --version` prints `0.1.0`. No re-pipe needed.
- [ ] Same flow on Ubuntu 24.04 fresh VM without cosign: installer detects `apt-get` → prompts with `sudo -E apt-get install -y cosign` → installs → succeeds.
- [ ] Same flow on Fedora 40 / RHEL 9 with `dnf`.
- [ ] Same flow on Arch / Manjaro with `pacman`.
- [ ] Same flow on Alpine with `apk`.
- [ ] `--auto-install-deps`: no prompts, installs unattended, exits 0 on success.
- [ ] `--no-install-deps`: does NOT install anything even if pkg manager detected; prints manual instructions; exits 1 if cosign missing.
- [ ] `--skip-verify`: unchanged behaviour — bypass verification entirely.
- [ ] `slsa-verifier` missing is STILL a warning (not a blocker) even without `--auto-install-deps`.
- [ ] On a host with no supported pkg manager (exotic distro, no brew, no apt/dnf/pacman/apk/nix): current manual-instruction error message fires unchanged.
- [ ] Installer prints the exact command it is about to run BEFORE running it, so a paranoid operator can Ctrl-C before elevation.
- [ ] If the user refuses the prompt (`n`), installer prints manual instructions + exit code 1 (not zero — install didn't complete).
- [ ] Sudo fallback: if not root and sudo missing, clear error message instead of cryptic exec failure.
- [ ] `shellcheck install.sh` clean (treat warnings as errors in CI).

## Execution Strategy

### Wave 1 (sequential)

| Group | Agent | Description |
|-------|-------|-------------|
| 1 | engineer | Package-manager detection helpers (`detect_pkg_manager`, `suggest_install_cmd`) + auto-install flow for cosign on all 6 targets (brew/apt/dnf/pacman/apk/nix) with interactive prompt |
| 2 | engineer | Non-interactive flags (`--auto-install-deps`, `--no-install-deps`) + slsa-verifier auto-install offer with same detection logic |
| 3 | engineer | Fresh-host smoke tests across all supported platforms + README update + `docs/install/troubleshooting.md` + shellcheck gate |

## Execution Groups

### Group 1: Package-Manager Detection + Cosign Auto-Install Flow

**Goal:** On a fresh host with no cosign, the installer detects the pkg manager and offers to install cosign with explicit consent — no re-pipe required.

**Deliverables:**
1. `detect_pkg_manager()` helper: probes `brew`, `apt-get`, `dnf`, `yum`, `pacman`, `apk`, `nix-env` / `nix profile` in that order. Returns the name + the install command template (including `sudo -E` prefix where needed).
2. `suggest_install_cmd(pkg)` helper: formats the exact command line the installer would run.
3. Replaced current `✗ cosign not on PATH...` hard-fail for cases where a pkg manager IS detected:
   - Print the suggested install command
   - Interactive prompt `[Y/n]` (default yes)
   - Accept → `exec` the command (inheriting stdin/stdout/stderr)
   - Re-probe `command -v cosign` after install; if still missing, fail loudly with the real error
4. Preserve the old hard-fail path when NO pkg manager detected.
5. No change to the `--skip-verify` bypass path.

**Acceptance Criteria:**
- [ ] `command -v cosign` probe runs exactly once upfront (no redundant checks).
- [ ] On macOS with `brew` present: prompt shows `Will run: brew install cosign. [Y/n]` → accepting installs + proceeds without re-pipe.
- [ ] On Ubuntu with `apt-get` present + not-root: prompt shows `Will run: sudo -E apt-get install -y cosign. [Y/n]`.
- [ ] On a host with no supported pkg manager: current error message fires unchanged (manual-install URL + `--skip-verify` hint).
- [ ] If user declines (`n`): installer exits 1 with a printed manual-install command the operator can paste.
- [ ] Cosign install failure (network, repo unavailable, etc.) prints the underlying stderr and exits 1.

**Validation:**
```bash
# On a fresh macOS VM without cosign:
curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/dev/install.sh | bash
# Accept the prompt; expect full install ending with `✓ aegis v0.1.0 installed`.

# On a Ubuntu 24.04 fresh VM without cosign:
curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/dev/install.sh | bash
# Accept `sudo -E apt-get install -y cosign` prompt; expect full install.

# Negative: decline the prompt, verify exit 1 + manual instructions.
```

**depends-on:** none

---

### Group 2: Non-Interactive Flags + slsa-verifier Auto-Install Offer

**Goal:** CI + automation paths get a clean flag to skip prompts; slsa-verifier gets the same detect-and-offer treatment, but as an OPTIONAL prompt since SLSA is not strictly required.

**Deliverables:**
1. `--auto-install-deps` flag: assumes Y on every dep-install prompt. Logs `auto-install-deps mode: will install <pkg> without prompting`.
2. `--no-install-deps` flag: refuses to install anything. If a missing dep would block verification, prints manual instructions and exits 1. Mutually exclusive with `--auto-install-deps` (flag-order conflict errors loudly).
3. `slsa-verifier` auto-install offer:
   - When missing, with a supported pkg manager: prompt `Install slsa-verifier for full 3-layer attestation check? [y/N]` (NOTE the default: N — SLSA is opt-in).
   - `--auto-install-deps` promotes this to auto-yes.
   - Without a pkg manager: print manual-install URL + continue without it (current warning-only behavior).
4. Help text (`--help`) updated to explain all three flags (`--skip-verify`, `--auto-install-deps`, `--no-install-deps`) clearly.

**Acceptance Criteria:**
- [ ] `bash install.sh --auto-install-deps` on a fresh host: installs cosign + slsa-verifier + aegis, no prompts.
- [ ] `bash install.sh --no-install-deps` with cosign missing: prints manual instructions for cosign + exits 1.
- [ ] Conflicting flags (`--auto-install-deps --no-install-deps`): error with clear message + exit 2.
- [ ] slsa-verifier prompt defaults to N (must be opt-in).
- [ ] `--skip-verify` overrides everything: no deps offered, no verification, just install.

**Validation:**
```bash
# CI-mode install:
curl -fsSL .../install.sh | bash -s -- --auto-install-deps
# expect: cosign and slsa-verifier both present afterwards; install succeeded without prompts.

# Refuse-install mode:
curl -fsSL .../install.sh | bash -s -- --no-install-deps
# expect: if cosign missing, exit 1 with manual instructions; no install.

# Conflict:
bash install.sh --auto-install-deps --no-install-deps
# expect: exit 2 with clear error.
```

**depends-on:** Group 1

---

### Group 3: Cross-Platform Smoke Tests + Docs + shellcheck Gate

**Goal:** Validate the UX on every supported platform + document the install flow + add shellcheck to CI so the installer stays clean.

**Deliverables:**
1. `test/install/` harness: lightweight container-based smoke test that runs the installer inside fresh images for:
   - `ubuntu:24.04`
   - `debian:12`
   - `fedora:40`
   - `archlinux:latest`
   - `alpine:3.19`
   - (macOS: skipped in CI; validated manually by a human.)
2. `scripts/test-install.sh`: local harness that runs the above containers end-to-end and asserts `aegis --version` prints the expected version.
3. CI workflow `.github/workflows/install-smoke-test.yml`: runs `scripts/test-install.sh` on every PR that touches `install.sh`.
4. `shellcheck install.sh` added to the same workflow; treat warnings as errors.
5. README "Install" section updated to reflect the new flow (one-liner just works on macOS/Linux; no manual cosign install for common distros).
6. `docs/install/troubleshooting.md` (new) covers:
   - "No pkg manager detected" fallback
   - Sudo denied / password prompt timed out
   - cosign install failed (network, repo down)
   - Air-gapped install path
   - Windows users: direction to the future PowerShell installer issue

**Acceptance Criteria:**
- [ ] `scripts/test-install.sh` passes on all 5 Linux containers.
- [ ] macOS smoke test documented as a manual playbook (human-run, checked off during release candidate verification).
- [ ] CI workflow fires on PRs touching `install.sh` and passes on clean diffs.
- [ ] `shellcheck install.sh` runs in CI and any warning fails the job.
- [ ] README reflects the new behaviour (no stale `brew install cosign` prerequisite for the common path).
- [ ] `docs/install/troubleshooting.md` exists and covers the 5 failure modes above.

**Validation:**
```bash
bash scripts/test-install.sh                                    # local run across containers
shellcheck install.sh                                           # must be clean
gh workflow run install-smoke-test.yml --repo automagik-dev/aegis  # CI verification
```

**depends-on:** Group 2

---

## QA Criteria

- [ ] Fresh Mac (Apple Silicon, no cosign): `curl | bash` → prompts → accepts → aegis installed in < 60s.
- [ ] Fresh Ubuntu 24.04: same flow with sudo prompt. Password entered, install succeeds.
- [ ] Fresh Fedora 40: same via `dnf`.
- [ ] Fresh Arch: same via `pacman`.
- [ ] Fresh Alpine: same via `apk`.
- [ ] `curl | bash -s -- --auto-install-deps`: unattended install succeeds end-to-end.
- [ ] `curl | bash -s -- --no-install-deps` with cosign missing: exits 1 with manual instructions (no mutation).
- [ ] `curl | bash -s -- --skip-verify`: unchanged behaviour preserved.
- [ ] slsa-verifier prompt defaults to N; user must opt-in.
- [ ] Host with no pkg manager: current error path unchanged.
- [ ] `shellcheck install.sh` clean.
- [ ] CI workflow passes on dev.

## Assumptions / Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| `brew install cosign` / `apt install cosign` fail (repo unavailable, network down) | Medium | Capture stderr, print clearly, exit 1 with the underlying error. User knows what to fix. |
| User accidentally runs installer with `sudo curl \| sudo bash` and auto-installer prompts for sudo a second time | Low | Detect root early; skip the `sudo -E` prefix when already root. |
| Package manager detection false-positive (e.g., macOS with both `brew` and `apt` from a brew formula) | Low | Probe in priority order; brew wins on macOS regardless. |
| Alpine's `cosign` package is out-of-date or missing | Medium | If `apk add cosign` fails because the package doesn't exist, fall through to manual-install path with the cosign release URL. |
| User on a corporate Mac without Homebrew or admin rights | Medium | Manual-install path fires unchanged. Document in troubleshooting.md with "install cosign via signed tarball from sigstore" steps. |
| `--auto-install-deps` ends up in a CI pipeline that shouldn't have sudo | Medium | Flag's stderr output is loud: "auto-install-deps: will exec `sudo -E apt install cosign`". Operators can inspect the CI log and catch mistakes. |
| Windows users try the one-liner and hit POSIX-shell errors | Low | Installer detects Windows via `uname` and prints a pointer to the (future) PowerShell installer issue + `--skip-verify` workaround via WSL. |

## Review Results

_Populated by `/review` after execution completes._

## Files to Create/Modify

```
install.sh                                  # modify: detect_pkg_manager + suggest_install_cmd + interactive flow + --auto-install-deps + --no-install-deps + slsa-verifier offer
scripts/test-install.sh                     # create: cross-container smoke test harness
test/install/Dockerfile.ubuntu-24           # create: minimal smoke-test image
test/install/Dockerfile.debian-12           # create
test/install/Dockerfile.fedora-40           # create
test/install/Dockerfile.archlinux           # create
test/install/Dockerfile.alpine-3.19         # create
.github/workflows/install-smoke-test.yml    # create: CI gate on install.sh changes (shellcheck + cross-container smoke)
README.md                                   # modify: Install section reflects new behaviour
docs/install/troubleshooting.md             # create: 5 failure-mode playbook
docs/install/npm-advanced.md                # modify: cross-link to troubleshooting.md
```
