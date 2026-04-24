#!/usr/bin/env bash
#
# aegis installer — zero-config, no-npm-interaction install.
#
#   curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/main/install.sh | bash -s -- --version v0.1.0
#   curl -fsSL https://raw.githubusercontent.com/automagik-dev/aegis/main/install.sh | bash -s -- --skip-verify   # air-gapped
#
# What this does:
#   1. Detects platform (macOS/Linux, x64/arm64).
#   2. Fetches the requested release from the automagik-dev/aegis GitHub Releases
#      (default: latest). Downloads the tarball + cosign .sig + .cert + SLSA
#      provenance.
#   3. Verifies the cosign keyless signature (requires `cosign` on PATH unless
#      --skip-verify) + SLSA provenance (requires `slsa-verifier` unless
#      --skip-verify).
#   4. Extracts to $AEGIS_HOME (default: ~/.aegis/).
#   5. Symlinks $PREFIX/bin/aegis (default: ~/.local/bin/aegis) → the installed
#      payload. Prints a path-setup hint if $PREFIX/bin is not already on PATH.
#
# What this does NOT do:
#   - Touch your ~/.npmrc, ~/.bun, ~/.cache, or any package-manager config.
#   - Install anything to /usr/local/ without sudo.
#   - Contact npmjs.com. At all. Ever.

set -euo pipefail

REPO="automagik-dev/aegis"
VERSION="${AEGIS_VERSION:-latest}"
AEGIS_HOME="${AEGIS_HOME:-$HOME/.aegis}"
PREFIX="${AEGIS_PREFIX:-$HOME/.local}"
SKIP_VERIFY="${AEGIS_SKIP_VERIFY:-0}"

# ----- argument parsing ------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --version)    VERSION="$2"; shift 2;;
    --home)       AEGIS_HOME="$2"; shift 2;;
    --prefix)     PREFIX="$2"; shift 2;;
    --skip-verify) SKIP_VERIFY=1; shift;;
    --help|-h)
      sed -n '3,25p' "$0" | sed 's/^# \?//'
      exit 0;;
    *)
      printf 'aegis install: unknown flag: %s\n' "$1" >&2
      exit 1;;
  esac
done

# ----- logging helpers -------------------------------------------------------
c_info()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
c_ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
c_warn()  { printf '\033[1;33m⚠\033[0m %s\n' "$*" >&2; }
c_fail()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ----- platform detection ----------------------------------------------------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  linux|darwin) ;;
  *) c_fail "Unsupported OS: $OS (aegis supports macOS and Linux; WSL runs as linux).";;
esac

case "$ARCH" in
  x86_64|amd64) ARCH=x64;;
  arm64|aarch64) ARCH=arm64;;
  *) c_fail "Unsupported arch: $ARCH (aegis supports x64 and arm64).";;
esac

c_info "Platform detected: $OS/$ARCH"

# ----- dependency checks -----------------------------------------------------
for cmd in curl tar node; do
  command -v "$cmd" >/dev/null 2>&1 || c_fail "Missing required tool: $cmd"
done

NODE_MAJOR=$(node --version | sed 's/^v//' | cut -d. -f1)
[ "$NODE_MAJOR" -ge 20 ] || c_fail "aegis requires Node.js >=20 (you have $(node --version))"

if [ "$SKIP_VERIFY" != "1" ]; then
  command -v cosign >/dev/null 2>&1 || c_fail "cosign not on PATH. Install from https://github.com/sigstore/cosign/releases or rerun with --skip-verify (not recommended)."
  command -v slsa-verifier >/dev/null 2>&1 || c_warn "slsa-verifier not found — SLSA provenance check will be skipped. Install from https://github.com/slsa-framework/slsa-verifier/releases for the full 3-layer attestation check."
fi

# ----- resolve release -------------------------------------------------------
if [ "$VERSION" = "latest" ]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | \
    grep '"tag_name":' | head -1 | sed 's/.*"tag_name": "\(.*\)".*/\1/')
  [ -n "$VERSION" ] || c_fail "Could not resolve latest release tag from GitHub API."
fi

case "$VERSION" in
  v*) ;;
  *)  VERSION="v$VERSION";;
esac

c_info "Installing aegis $VERSION"

# ----- download tarball + signatures -----------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BASE_URL="https://github.com/$REPO/releases/download/$VERSION"

# npm pack names the tarball `automagik-dev-aegis-<version-without-v>.tgz` for the
# @automagik-dev scope. We try a few patterns so a future rename doesn't break us.
VERSION_BARE="${VERSION#v}"
CANDIDATES=(
  "automagik-dev-aegis-${VERSION_BARE}.tgz"
  "automagik-dev-aegis-${VERSION}.tgz"
  "aegis-${VERSION_BARE}.tgz"
)

TARBALL=""
for candidate in "${CANDIDATES[@]}"; do
  c_info "Probing release asset: $candidate"
  if curl -fsSLI "$BASE_URL/$candidate" >/dev/null 2>&1; then
    TARBALL="$candidate"
    break
  fi
done

[ -n "$TARBALL" ] || c_fail "Could not find an aegis tarball in release $VERSION. See https://github.com/$REPO/releases/$VERSION for the actual asset name."

c_info "Downloading $TARBALL..."
curl -fsSL "$BASE_URL/$TARBALL"       -o "$TMP/$TARBALL"
curl -fsSL "$BASE_URL/$TARBALL.sig"   -o "$TMP/$TARBALL.sig"   2>/dev/null || c_warn "No .sig asset — cosign verification cannot run."
curl -fsSL "$BASE_URL/$TARBALL.cert"  -o "$TMP/$TARBALL.cert"  2>/dev/null || c_warn "No .cert asset — cosign verification cannot run."
curl -fsSL "$BASE_URL/provenance.intoto.jsonl" -o "$TMP/provenance.intoto.jsonl" 2>/dev/null || c_warn "No provenance asset — SLSA verification cannot run."

# ----- verify ----------------------------------------------------------------
if [ "$SKIP_VERIFY" = "1" ]; then
  c_warn "--skip-verify passed: cosign and SLSA verification BYPASSED. Only safe for air-gapped mirrors with out-of-band verification."
else
  c_info "Verifying cosign keyless signature..."
  cosign verify-blob \
    --certificate-identity-regexp "^https://github.com/$REPO/\\.github/workflows/release\\.yml@" \
    --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
    --signature "$TMP/$TARBALL.sig" \
    --certificate "$TMP/$TARBALL.cert" \
    "$TMP/$TARBALL" >/dev/null 2>&1 || c_fail "cosign signature verification FAILED. Do not install."
  c_ok "cosign signature verified (OIDC identity pinned to release.yml@$VERSION)"

  if command -v slsa-verifier >/dev/null 2>&1 && [ -f "$TMP/provenance.intoto.jsonl" ]; then
    c_info "Verifying SLSA L3 provenance..."
    slsa-verifier verify-artifact "$TMP/$TARBALL" \
      --provenance-path "$TMP/provenance.intoto.jsonl" \
      --source-uri "github.com/$REPO" >/dev/null 2>&1 || c_fail "SLSA provenance verification FAILED. Do not install."
    c_ok "SLSA L3 provenance verified"
  fi
fi

# ----- install --------------------------------------------------------------
INSTALL_DIR="$AEGIS_HOME/$VERSION"
c_info "Extracting to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP/$TARBALL" -C "$INSTALL_DIR" --strip-components=1

c_info "Installing dependencies..."
( cd "$INSTALL_DIR" && npm install --omit=dev --no-audit --no-fund --silent >/dev/null 2>&1 ) || c_fail "npm install of aegis dependencies failed inside $INSTALL_DIR."

# Record install metadata for `aegis update` to use later.
cat > "$AEGIS_HOME/install.json" <<EOF
{
  "version": "$VERSION",
  "installed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "install_dir": "$INSTALL_DIR",
  "platform": "$OS/$ARCH",
  "skip_verify": $SKIP_VERIFY
}
EOF
chmod 600 "$AEGIS_HOME/install.json"

# Atomic symlink swap.
mkdir -p "$PREFIX/bin"
ln -sfn "$INSTALL_DIR/dist/cli.js" "$PREFIX/bin/aegis.tmp"
chmod +x "$INSTALL_DIR/dist/cli.js"
mv "$PREFIX/bin/aegis.tmp" "$PREFIX/bin/aegis"

c_ok "aegis $VERSION installed to $INSTALL_DIR"
c_ok "Symlinked: $PREFIX/bin/aegis"

case ":$PATH:" in
  *":$PREFIX/bin:"*) ;;
  *)
    c_warn "$PREFIX/bin is not on your PATH. Add it to your shell profile:"
    printf '    export PATH="%s/bin:$PATH"\n' "$PREFIX" >&2;;
esac

printf '\n%s\n' "Next: try 'aegis --help' or 'aegis scan --all-homes --root \"\$PWD\"'"
