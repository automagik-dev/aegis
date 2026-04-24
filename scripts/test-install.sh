#!/usr/bin/env bash
#
# aegis installer cross-distro smoke test.
#
# Builds a minimal docker image per supported Linux distro, runs the local
# install.sh inside the container with --auto-install-deps (non-interactive),
# and asserts `aegis --version` reports the expected release.
#
# Usage:
#   bash scripts/test-install.sh                          # all distros, default version
#   bash scripts/test-install.sh --version v0.1.1         # pin a different release
#   bash scripts/test-install.sh --distros ubuntu-24,alpine-3.19
#   bash scripts/test-install.sh --skip-verify            # bypass cosign on every run
#   bash scripts/test-install.sh --help
#
# Environment overrides (flags win over env):
#   AEGIS_TEST_VERSION   release tag passed to install.sh (default: v0.1.0)
#   AEGIS_TEST_DISTROS   comma-separated subset of distros to run
#   AEGIS_TEST_SKIP_VERIFY=1  pass --skip-verify to the in-container installer
#
# Exit codes:
#   0  every selected distro passed
#   1  one or more distros failed (last 20 lines printed for each failure)
#   2  invocation error (bad flag, missing docker)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKERFILE_DIR="$REPO_ROOT/test/install"

ALL_DISTROS=(ubuntu-24 debian-12 fedora-40 archlinux alpine-3.19)

VERSION="${AEGIS_TEST_VERSION:-v0.1.0}"
DISTROS_CSV="${AEGIS_TEST_DISTROS:-}"
SKIP_VERIFY="${AEGIS_TEST_SKIP_VERIFY:-0}"

usage() {
  sed -n '3,24p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)     VERSION="$2"; shift 2 ;;
    --distros)     DISTROS_CSV="$2"; shift 2 ;;
    --skip-verify) SKIP_VERIFY=1; shift ;;
    --help|-h)     usage; exit 0 ;;
    *) printf 'test-install: unknown flag: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

# Resolve the list of distros to run from CSV, validating each entry against
# ALL_DISTROS so a typo fails loudly instead of silently doing nothing.
declare -a DISTROS=()
if [ -n "$DISTROS_CSV" ]; then
  IFS=',' read -r -a requested <<< "$DISTROS_CSV"
  for d in "${requested[@]}"; do
    found=0
    for known in "${ALL_DISTROS[@]}"; do
      if [ "$d" = "$known" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -ne 1 ]; then
      printf 'test-install: unknown distro: %s\n' "$d" >&2
      printf 'known distros: %s\n' "${ALL_DISTROS[*]}" >&2
      exit 2
    fi
    DISTROS+=("$d")
  done
else
  DISTROS=("${ALL_DISTROS[@]}")
fi

if ! command -v docker >/dev/null 2>&1; then
  printf 'test-install: docker is not installed or not on PATH.\n' >&2
  printf 'Install docker (https://docs.docker.com/engine/install/) and re-run.\n' >&2
  exit 2
fi

# Trim leading "v" from the version once for the bare-version assertion.
VERSION_BARE="${VERSION#v}"

# Pretty-print helpers. Plain ASCII glyphs so the output is grep-friendly.
c_info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
c_ok()   { printf '\033[1;32m[ok]\033[0m %s\n' "$*"; }
c_fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; }

declare -a RESULTS=()
declare -a DURATIONS=()
OVERALL_RC=0

run_one() {
  local distro="$1"
  local dockerfile="$DOCKERFILE_DIR/Dockerfile.$distro"
  local image="aegis-install-test:$distro"

  if [ ! -f "$dockerfile" ]; then
    c_fail "$distro: Dockerfile not found at $dockerfile"
    RESULTS+=("FAIL")
    DURATIONS+=("0")
    OVERALL_RC=1
    return
  fi

  c_info "[$distro] building image"
  local build_log
  build_log="$(mktemp)"
  if ! docker build -t "$image" -f "$dockerfile" "$REPO_ROOT" >"$build_log" 2>&1; then
    c_fail "$distro: docker build failed (last 20 lines):"
    tail -n 20 "$build_log" >&2 || true
    rm -f "$build_log"
    RESULTS+=("FAIL")
    DURATIONS+=("0")
    OVERALL_RC=1
    return
  fi
  rm -f "$build_log"

  # Compose the in-container command. install.sh is bind-mounted at
  # /work/install.sh so we don't have to bake a copy into every image.
  local installer_args=(--auto-install-deps --version "$VERSION")
  if [ "$SKIP_VERIFY" = "1" ]; then
    installer_args+=(--skip-verify)
  fi

  # Quote the version for shell interpolation inside the container's bash -c.
  local in_container_cmd
  in_container_cmd=$(cat <<EOF
set -e
bash /work/install.sh ${installer_args[*]}
export PATH="\$HOME/.local/bin:\$PATH"
ver="\$(aegis --version 2>/dev/null || true)"
printf 'aegis-version-output: %s\n' "\$ver"
case "\$ver" in
  *"$VERSION_BARE"*) exit 0 ;;
  *) printf 'aegis --version did not contain %s (got: %s)\n' "$VERSION_BARE" "\$ver" >&2; exit 1 ;;
esac
EOF
)

  c_info "[$distro] running installer"
  local run_log
  run_log="$(mktemp)"
  local started ended duration
  started=$(date +%s)
  if docker run --rm \
        -v "$REPO_ROOT/install.sh:/work/install.sh:ro" \
        "$image" \
        bash -c "$in_container_cmd" >"$run_log" 2>&1; then
    ended=$(date +%s)
    duration=$((ended - started))
    c_ok "$distro: aegis --version reports $VERSION_BARE (took ${duration}s)"
    RESULTS+=("OK")
    DURATIONS+=("$duration")
  else
    ended=$(date +%s)
    duration=$((ended - started))
    c_fail "$distro: installer or version check failed (last 20 lines):"
    tail -n 20 "$run_log" >&2 || true
    RESULTS+=("FAIL")
    DURATIONS+=("$duration")
    OVERALL_RC=1
  fi
  rm -f "$run_log"
}

c_info "Testing aegis installer for version: $VERSION"
c_info "Distros: ${DISTROS[*]}"

for distro in "${DISTROS[@]}"; do
  run_one "$distro"
done

# Summary table. distro | result | duration. Plain ASCII; pipe-delimited so
# downstream tooling (grep / awk / CI annotations) parses cleanly.
printf '\n'
printf '%-14s | %-6s | %s\n' "distro" "result" "duration"
printf -- '---------------+--------+---------\n'
for i in "${!DISTROS[@]}"; do
  local_distro="${DISTROS[$i]}"
  local_result="${RESULTS[$i]}"
  local_duration="${DURATIONS[$i]}s"
  case "$local_result" in
    OK)   glyph="ok" ;;
    FAIL) glyph="FAIL" ;;
    *)    glyph="$local_result" ;;
  esac
  printf '%-14s | %-6s | %s\n' "$local_distro" "$glyph" "$local_duration"
done

if [ "$OVERALL_RC" -ne 0 ]; then
  printf '\nOne or more distros FAILED. See logs above.\n' >&2
fi

exit "$OVERALL_RC"
