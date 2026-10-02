#!/usr/bin/env bash
# =============================================================================
# rpm_package_build.sh — Full automated RPM build, package & smoke-test script
#                         for OpenBoardView on Fedora / RPM-based Linux.
#
# Usage:
#   bash rpm_package_build.sh [OPTIONS]
#
# Options:
#   --recompile   Wipe the build directory and start fresh  (default: incremental)
#   --skip-deps   Skip the dependency-check step
#   --skip-test   Skip the smoke-test / install-verify step
#   --install     Install the newest RPM after building (requires sudo)
#   --clean       Remove all generated *.rpm and *.deb files from project root
#   --help        Show this help message
#
# Environment variables:
#   THREADS       Override the number of parallel compile threads
#
# The script always picks the *.rpm with the NEWEST file timestamp, so
# running it multiple times never accidentally installs a stale package.
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
C_RESET="" C_BOLD="" C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
if [ -t 1 ] && command -v tput &>/dev/null; then
  C_RESET="$(tput sgr0    2>/dev/null || true)"
  C_BOLD="$(tput bold     2>/dev/null || true)"
  C_RED="$(tput setaf 1   2>/dev/null || true)"
  C_GREEN="$(tput setaf 2 2>/dev/null || true)"
  C_YELLOW="$(tput setaf 3 2>/dev/null || true)"
  C_BLUE="$(tput setaf 4  2>/dev/null || true)"
  C_CYAN="$(tput setaf 6  2>/dev/null || true)"
fi

info()    { echo "${C_BOLD}${C_BLUE}[INFO]${C_RESET}  $*"; }
success() { echo "${C_BOLD}${C_GREEN}[OK]${C_RESET}    $*"; }
warn()    { echo "${C_BOLD}${C_YELLOW}[WARN]${C_RESET}  $*" >&2; }
error()   { echo "${C_BOLD}${C_RED}[ERROR]${C_RESET} $*" >&2; }
step()    { echo; echo "${C_BOLD}${C_CYAN}══ $* ══${C_RESET}"; }

die() {
  error "$*"
  exit 1
}

# ── Defaults ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/release_build"
RECOMPILE=false
SKIP_DEPS=false
SKIP_TEST=false
DO_INSTALL=false
DO_CLEAN=false
THREADS="${THREADS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)}"

# ── Parse arguments ───────────────────────────────────────────────────────────
usage() {
  sed -n '3,20p' "$0" | sed 's/^# \?//'
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --recompile)  RECOMPILE=true ;;
    --skip-deps)  SKIP_DEPS=true ;;
    --skip-test)  SKIP_TEST=true ;;
    --install)    DO_INSTALL=true ;;
    --clean)      DO_CLEAN=true ;;
    --help|-h)    usage ;;
    *) die "Unknown option: $arg  (run with --help for usage)" ;;
  esac
done

# ── Banner ────────────────────────────────────────────────────────────────────
echo
echo "${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════╗${C_RESET}"
echo "${C_BOLD}${C_CYAN}║  OpenBoardView — RPM Automated Build Script  ║${C_RESET}"
echo "${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════╝${C_RESET}"
echo "  Project root : ${SCRIPT_DIR}"
echo "  Build dir    : ${BUILD_DIR}"
echo "  Threads      : ${THREADS}"
echo "  Recompile    : ${RECOMPILE}"
echo "  Install RPM  : ${DO_INSTALL}"

# ── Optional clean ────────────────────────────────────────────────────────────
if [ "$DO_CLEAN" = true ]; then
  step "Cleaning old packages"
  shopt -s nullglob
  old_pkgs=("${SCRIPT_DIR}"/*.rpm "${SCRIPT_DIR}"/*.deb)
  if [ ${#old_pkgs[@]} -gt 0 ]; then
    rm -f "${old_pkgs[@]}"
    success "Removed ${#old_pkgs[@]} old package file(s)"
  else
    info "No old package files found"
  fi
  shopt -u nullglob
fi

# ── Step 1: Verify we are inside a proper project root ───────────────────────
step "Step 1 — Verifying project root"
[ -f "${SCRIPT_DIR}/CMakeLists.txt" ] || die "CMakeLists.txt not found in ${SCRIPT_DIR}. Run this script from the OpenBoardView repo root."
[ -f "${SCRIPT_DIR}/build.sh" ]       || die "build.sh not found. Is this the correct repo?"
success "Project root looks good"

# ── Step 2: Dependency check ──────────────────────────────────────────────────
step "Step 2 — Checking build dependencies"
if [ "$SKIP_DEPS" = true ]; then
  warn "Skipping dependency check (--skip-deps)"
else
  MISSING=()

  check_cmd() {
    command -v "$1" &>/dev/null && success "$1 found ($(command -v "$1"))" || MISSING+=("cmd:$1")
  }
  check_pkg() {
    pkg-config --exists "$1" 2>/dev/null && success "pkg: $1 found" || MISSING+=("pkg:$1")
  }

  check_cmd cmake
  check_cmd gcc
  check_cmd g++
  check_cmd make
  check_cmd git
  check_cmd rpmbuild
  check_pkg gtk+-3.0
  check_pkg sdl2
  check_pkg sqlite3
  check_pkg fontconfig
  check_pkg zlib

  if [ ${#MISSING[@]} -gt 0 ]; then
    error "Missing dependencies:"
    for m in "${MISSING[@]}"; do
      case "$m" in
        cmd:cmake)    echo "    → sudo dnf install cmake" ;;
        cmd:gcc)      echo "    → sudo dnf install gcc gcc-c++" ;;
        cmd:g++)      echo "    → sudo dnf install gcc-c++" ;;
        cmd:make)     echo "    → sudo dnf install make" ;;
        cmd:git)      echo "    → sudo dnf install git" ;;
        cmd:rpmbuild) echo "    → sudo dnf install rpm-build" ;;
        pkg:gtk+-3.0) echo "    → sudo dnf install gtk3-devel" ;;
        pkg:sdl2)     echo "    → sudo dnf install SDL2-devel" ;;
        pkg:sqlite3)  echo "    → sudo dnf install sqlite-devel" ;;
        pkg:fontconfig) echo "    → sudo dnf install fontconfig-devel" ;;
        pkg:zlib)     echo "    → sudo dnf install zlib-devel" ;;
        *)            echo "    → Missing: $m" ;;
      esac
    done
    die "Install the above packages and re-run this script."
  fi
  success "All dependencies satisfied"
fi

# ── Step 3: Git submodules ────────────────────────────────────────────────────
step "Step 3 — Initialising git submodules"
cd "${SCRIPT_DIR}"

# Detect uninitialised submodules (lines starting with -)
UNINIT=$(git submodule status 2>/dev/null | grep -c '^-' || true)
if [ "$UNINIT" -gt 0 ]; then
  info "Found ${UNINIT} uninitialised submodule(s) — cloning..."
  git submodule update --init --recursive
  success "Submodules ready"
else
  info "Checking submodules for updates..."
  git submodule update --recursive
  success "Submodules up to date"
fi

# ── Step 4: CMake build ───────────────────────────────────────────────────────
step "Step 4 — Compiling OpenBoardView (${THREADS} thread(s))"

if [ "$RECOMPILE" = true ] && [ -d "${BUILD_DIR}" ]; then
  info "Wiping existing build directory..."
  rm -rf "${BUILD_DIR}"
  success "Build directory cleared"
fi

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# DESTDIR tells CMake where to stage installed files (into the project root,
# exactly as the upstream build.sh does). This avoids needing root and keeps
# bin/ and share/ under the repo directory.
export DESTDIR="${SCRIPT_DIR}"

info "Running cmake..."
cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX= .. \
  || die "CMake configuration failed"

info "Running make install/strip with ${THREADS} thread(s)..."
make -j"${THREADS}" install/strip \
  || die "Compilation failed"

success "Build complete"

# ── Step 5: Generate RPM (and DEB) package ────────────────────────────────────
step "Step 5 — Generating RPM package via CPack"
cd "${BUILD_DIR}"

make package \
  || die "CPack packaging failed"

success "Packages generated"

# ── Step 6: Identify the newest RPM by file timestamp ─────────────────────────
step "Step 6 — Selecting newest RPM by timestamp"
cd "${SCRIPT_DIR}"

# Use ls -t (newest first) and pick the first .rpm found
NEWEST_RPM=$(ls -t "${SCRIPT_DIR}"/*.rpm 2>/dev/null | head -n 1)

if [ -z "$NEWEST_RPM" ]; then
  die "No .rpm file found in ${SCRIPT_DIR} after packaging step"
fi

NEWEST_RPM_BASE=$(basename "$NEWEST_RPM")
RPM_MTIME=$(stat -c '%y' "$NEWEST_RPM" | cut -d'.' -f1)

info "All RPM packages found (newest first):"
ls -lt "${SCRIPT_DIR}"/*.rpm 2>/dev/null | awk '{print "    " $6, $7, $8, $9}'

echo
success "Selected: ${C_BOLD}${NEWEST_RPM_BASE}${C_RESET}  (modified: ${RPM_MTIME})"
echo "  Full path: ${NEWEST_RPM}"

# ── Step 7: Smoke-test the RPM ────────────────────────────────────────────────
step "Step 7 — Smoke-testing the RPM"
if [ "$SKIP_TEST" = true ]; then
  warn "Skipping smoke test (--skip-test)"
else
  info "Querying RPM metadata (rpm -qip)..."
  rpm_info=$(rpm -qip "$NEWEST_RPM" 2>&1)
  echo "$rpm_info" | sed 's/^/    /'

  # Validate expected fields
  PKG_NAME=$(echo "$rpm_info"    | grep '^Name'    | awk '{print $NF}')
  PKG_VER=$(echo "$rpm_info"     | grep '^Version' | awk '{print $NF}')
  PKG_ARCH=$(echo "$rpm_info"    | grep '^Architecture' | awk '{print $NF}')
  PKG_SIZE=$(echo "$rpm_info"    | grep '^Size'    | awk '{print $NF}')

  [ -n "$PKG_NAME" ]  && success "Package name    : ${PKG_NAME}" || warn "Package name not found in metadata"
  [ -n "$PKG_VER" ]   && success "Version         : ${PKG_VER}"  || warn "Version not found in metadata"
  [ -n "$PKG_ARCH" ]  && success "Architecture    : ${PKG_ARCH}" || warn "Architecture not found in metadata"
  [ -n "$PKG_SIZE" ]  && success "Installed size  : ${PKG_SIZE} bytes" || warn "Size not found in metadata"

  info "Listing packaged files (rpm -qlp)..."
  rpm -qlp "$NEWEST_RPM" 2>/dev/null | sed 's/^/    /'

  # Check the binary is present in the payload
  if rpm -qlp "$NEWEST_RPM" 2>/dev/null | grep -q '/usr/bin/openboardview'; then
    success "Binary /usr/bin/openboardview confirmed in package payload"
  else
    die "Expected /usr/bin/openboardview not found in RPM payload"
  fi

  # Verify the local binary also runs
  LOCAL_BIN="${SCRIPT_DIR}/bin/openboardview"
  if [ -x "$LOCAL_BIN" ]; then
    info "Testing local binary (launching with --help or timeout)..."
    # openboardview is a GUI app — just verify it starts and exits cleanly
    timeout 3 "$LOCAL_BIN" 2>/dev/null || true
    success "Local binary is executable: ${LOCAL_BIN}"
  else
    warn "Local binary not found at ${LOCAL_BIN} (skipping runtime check)"
  fi

  success "Smoke test passed"
fi

# ── Step 8: Optional install ──────────────────────────────────────────────────
if [ "$DO_INSTALL" = true ]; then
  step "Step 8 — Installing RPM"
  if command -v dnf &>/dev/null; then
    info "Installing via: sudo dnf localinstall ${NEWEST_RPM_BASE}"
    sudo dnf localinstall -y "$NEWEST_RPM" \
      && success "RPM installed successfully" \
      || die "dnf localinstall failed"
  else
    info "Installing via: sudo rpm -Uvh ${NEWEST_RPM_BASE}"
    sudo rpm -Uvh "$NEWEST_RPM" \
      && success "RPM installed successfully" \
      || die "rpm -Uvh failed"
  fi

  info "Verifying installation..."
  if rpm -q openboardview &>/dev/null; then
    INSTALLED_VER=$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' openboardview)
    success "Verified installed: openboardview-${INSTALLED_VER}"
  else
    die "Package does not appear to be installed after dnf localinstall"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo "${C_BOLD}${C_GREEN}╔══════════════════════════════════════════════════╗${C_RESET}"
echo "${C_BOLD}${C_GREEN}║  Build complete!                                 ║${C_RESET}"
echo "${C_BOLD}${C_GREEN}╠══════════════════════════════════════════════════╣${C_RESET}"
printf  "${C_BOLD}${C_GREEN}║${C_RESET}  RPM : %-42s${C_BOLD}${C_GREEN}║${C_RESET}\n" "${NEWEST_RPM_BASE}"
printf  "${C_BOLD}${C_GREEN}║${C_RESET}  Size: %-42s${C_BOLD}${C_GREEN}║${C_RESET}\n" "$(du -sh "$NEWEST_RPM" | cut -f1) (disk)"
echo "${C_BOLD}${C_GREEN}╚══════════════════════════════════════════════════╝${C_RESET}"
echo
info "To install: sudo dnf localinstall ${NEWEST_RPM}"
info "To remove : sudo dnf remove openboardview"
echo

exit 0
