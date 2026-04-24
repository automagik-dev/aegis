# Install troubleshooting

The aegis installer (`install.sh`) tries hard to "just work" on macOS and the
big-five Linux distros. This page collects the known failure modes when it
doesn't — what you see, why it happens, and the fix.

> **TL;DR escape hatches:**
> `--auto-install-deps` (assume Y, unattended), `--no-install-deps` (refuse to
> mutate the host), `--skip-verify` (air-gapped only — bypasses cosign + SLSA).

---

## 1. "No package manager detected"

**Symptom.** Installer prints something like:

```
✗ cosign not on PATH and no supported package manager detected
  (brew/apt-get/dnf/yum/pacman/apk/nix). Install from
  https://github.com/sigstore/cosign/releases or rerun with --skip-verify.
```

**Cause.** You're on a distro the installer doesn't probe — common cases are
Void Linux, Gentoo, Slackware, the BSDs, custom Buildroot images, or a stripped
container that removed its package manager. The installer refuses to guess
because the wrong guess could mutate the wrong package database.

**Fix — recommended.** Install cosign manually from the upstream Sigstore
release page, then re-run the installer:

```bash
# Linux x64 — adjust for your arch as needed.
curl -fsSL -o cosign \
  https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
chmod +x cosign
sudo mv cosign /usr/local/bin/
curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/main/install.sh | bash
```

**Fix — last resort.** If you can't or won't install cosign, run the installer
with `--skip-verify`. This bypasses cosign **and** SLSA verification, so the
binary is no longer cryptographically attested. Only acceptable for air-gapped
mirrors with out-of-band verification:

```bash
curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/main/install.sh \
  | bash -s -- --skip-verify
```

---

## 2. Sudo denied / password prompt timed out

**Symptom.** On Linux, the installer offers to run something like
`sudo -E apt-get install -y cosign`, but `sudo` rejects you (`a password is
required`, `user is not in the sudoers file`, or the prompt times out).

**Cause.** Your account doesn't have sudo, or your sudo session has expired
and the `curl | bash` pipeline can't read your password from a tty.

**Fix.** Two options.

1. **Re-run the installer with `--no-install-deps`** so it never attempts a
   privileged install, then install cosign yourself with whatever path your
   org provides (admin help, package mirror, manual tarball):

   ```bash
   curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/main/install.sh \
     | bash -s -- --no-install-deps
   ```

   This will exit with a clear message telling you to install cosign first.
   Once cosign is on `PATH`, re-run the installer normally.

2. **Install cosign in a directory you own** (no sudo needed) — see the
   manual cosign install snippet in section 1 but drop the `sudo mv` and
   put the binary somewhere on your `$PATH`, e.g. `~/.local/bin/cosign`.

---

## 3. cosign install failed (network, repo down, 404)

**Symptom.** The installer runs the offered package-manager command and the
package manager fails. You see something like:

```
==> Installing cosign via apt-get...
E: Unable to locate package cosign
✗ cosign install failed via apt-get. Re-run after fixing, or rerun with
  --skip-verify (not recommended).
```

**Cause.** Common reasons:

- The mirror you're pointing at doesn't ship `cosign` (older Debian/Ubuntu
  before backports, or stale Alpine mirrors).
- Network is being filtered by a corporate proxy.
- The upstream repo is genuinely down at the moment.

**Fix.**

1. **Read the package manager's stderr above the aegis error line.** The
   installer streams the underlying tool's output unchanged so you can see
   exactly which mirror / URL failed. That message is almost always the
   actionable signal.
2. **Update your package index and retry.** `sudo apt-get update`,
   `sudo dnf makecache`, `pacman -Syy`, or `apk update` — then re-run the
   aegis installer.
3. **Fall back to manual cosign install.** Use the upstream Sigstore release
   tarball — see section 1.
4. **Still stuck?** File an issue at
   https://github.com/automagik-dev/aegis/issues with the full installer
   output (redact anything sensitive). Include your distro name + version
   (`cat /etc/os-release`) and which package manager fired.

---

## 4. Air-gapped machine (no internet to npm, GitHub, or Sigstore)

**Symptom.** None of `curl | bash`, package manager installs, or cosign
verification can reach the network. The installer's `--auto-install-deps`
path is unusable because there's no upstream to pull from.

**Cause.** You're behind a strict egress firewall, on a classified network,
on a build farm with no DNS, or testing in a hermetic CI environment.

**Fix — sneakernet the tarball.**

1. **On a connected host, download the signed release assets:**

   ```bash
   VERSION=v0.1.0
   REPO=automagik-dev/aegis
   BASE=https://github.com/$REPO/releases/download/$VERSION
   curl -fsSL -O "$BASE/automagik-dev-aegis-${VERSION#v}.tgz"
   curl -fsSL -O "$BASE/automagik-dev-aegis-${VERSION#v}.tgz.sig"
   curl -fsSL -O "$BASE/automagik-dev-aegis-${VERSION#v}.tgz.cert"
   curl -fsSL -O "$BASE/provenance.intoto.jsonl"
   curl -fsSL -O "$BASE/install.sh"
   ```

2. **Verify out-of-band on the connected host** (this is the moment to use
   cosign + slsa-verifier with full network access):

   ```bash
   cosign verify-blob \
     --certificate-identity-regexp "^https://github.com/$REPO/\\.github/workflows/release\\.yml@" \
     --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
     --signature "automagik-dev-aegis-${VERSION#v}.tgz.sig" \
     --certificate "automagik-dev-aegis-${VERSION#v}.tgz.cert" \
     "automagik-dev-aegis-${VERSION#v}.tgz"
   ```

3. **Copy the verified bundle** to the air-gapped host (USB, internal mirror,
   approved transfer mechanism — this is the "sneakernet" step).

4. **Run the installer with `--skip-verify`** because the air-gapped host
   cannot reach Sigstore / Fulcio / Rekor:

   ```bash
   bash install.sh --skip-verify --version "$VERSION"
   ```

   The installer will look for the tarball at the expected GitHub URL. For a
   fully offline workflow, host the bundle on an internal HTTP mirror and
   override `REPO` / use a custom installer fork that points at it. Document
   that override in your internal SOP — out of scope for the upstream
   installer.

---

## 5. Windows users

**Status.** Native Windows is **not** currently supported. The installer is a
POSIX shell script and assumes `bash`, `curl`, `tar`, `node`, `cosign` — none
of which ship as a coherent set on stock Windows.

**Fix today — use WSL.** Install Windows Subsystem for Linux (Ubuntu image is
fine), then follow the standard Linux install path inside the WSL shell:

```bash
# Inside WSL Ubuntu/Debian shell:
curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/main/install.sh | bash
```

The `aegis` binary lands inside the WSL filesystem at `~/.aegis/`. From PowerShell
you can invoke it via `wsl aegis scan ...`.

**Future — native PowerShell installer.** A native Windows installer is
tracked in https://github.com/automagik-dev/aegis/issues (search for
"PowerShell installer"). Until that lands, WSL is the supported path.

---

## Appendix: macOS manual smoke-test playbook

CI does not test macOS (no public Apple Silicon runners that support docker).
Each release candidate is verified manually using this checklist. Run on a
fresh user account (not your daily driver) so you exercise the "no cosign yet"
prompt path.

Step-by-step:

1. **Confirm a clean baseline.** `which cosign` should print nothing. If you
   already have cosign, `brew uninstall cosign` first.
2. **Install Homebrew if missing.**

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

3. **Install Node 22 (>=20 required).**

   ```bash
   brew install node@22
   ```

4. **Run the aegis installer.**

   ```bash
   curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/main/install.sh | bash
   ```

   - Expected: prompt "cosign not on PATH. Will run: `brew install cosign`. [Y/n]" — accept.
   - brew installs cosign in <60s.
   - Optional slsa-verifier prompt fires next (default N — decline).
   - Installer downloads the tarball, verifies the cosign signature, extracts
     to `~/.aegis/v0.1.0/`, and symlinks `~/.local/bin/aegis`.

5. **Verify the install.**

   ```bash
   command -v aegis
   aegis --version            # should print 0.1.0 (or the pinned version)
   aegis verify-install       # cosign + SLSA re-verified against the binary
   ```

6. **Clean up (optional).**

   ```bash
   rm -rf ~/.aegis ~/.local/bin/aegis
   brew uninstall cosign
   ```

If step 4 prompts unexpectedly, hangs, or the installer fails — open an issue
with the full transcript.

---

For npm / GitHub Packages install issues (the secondary distribution path),
see [`npm-advanced.md`](npm-advanced.md).
