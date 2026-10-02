# OpenBoardView — RPM Compilation Guide

> **Platform:** Fedora Linux Asahi Remix 44 (aarch64 / Apple Silicon)  
> **Package:** `openboardview-10.0.0-1.aarch64.rpm`  
> **Build Date:** 2026-10-03  
> **Build System:** CMake + CPack + rpmbuild

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start — Automated Script](#quick-start--automated-script)
3. [System Requirements](#system-requirements)
4. [Install Build Dependencies](#install-build-dependencies)
5. [Clone the Repository](#clone-the-repository)
6. [Initialize Git Submodules](#initialize-git-submodules)
7. [Manual Build Steps](#manual-build-steps)
8. [Generate the RPM Package](#generate-the-rpm-package)
9. [Install the RPM](#install-the-rpm)
10. [Package Contents](#package-contents)
11. [Troubleshooting](#troubleshooting)
12. [CI/CD Reference](#cicd-reference)

---

## Overview

OpenBoardView is an open-source viewer for PCB board layout files (`.brd`, `.bvr`, `.obv`, etc.). It uses **CMake** as its build system and **CPack** to generate distribution packages. On Linux, CPack produces both `.deb` (Debian/Ubuntu) and `.rpm` (Fedora/RHEL/openSUSE) packages in a single `make package` step.

```
Source → cmake → make → make package → .rpm + .deb
```

There are **two ways** to build the RPM:
- **Automated:** Use [`rpm_package_build.sh`](./rpm_package_build.sh) — handles everything end-to-end *(recommended)*
- **Manual:** Follow the step-by-step instructions in [Manual Build Steps](#manual-build-steps)

---

## Quick Start — Automated Script

The [`rpm_package_build.sh`](./rpm_package_build.sh) script automates the complete pipeline: dependency checks → submodule sync → compile → package → smoke-test. It always selects the RPM with the **newest file timestamp**, so running it multiple times never accidentally uses a stale package.

```bash
# Clone the repo
git clone https://github.com/akbar-npj/OpenBoardView.git
cd OpenBoardView

# Run the automated build (incremental — reuses existing build directory)
bash rpm_package_build.sh

# Or force a clean recompile from scratch
bash rpm_package_build.sh --recompile

# Build AND install in one step (requires sudo)
bash rpm_package_build.sh --recompile --install
```

### Script options

| Flag | Description |
|---|---|
| `--recompile` | Wipe `release_build/` and start fresh |
| `--install` | Install the newly built RPM via `dnf localinstall` (needs sudo) |
| `--clean` | Delete old `*.rpm` / `*.deb` files from the project root before building |
| `--skip-deps` | Skip the dependency-check step |
| `--skip-test` | Skip the smoke-test / install-verify step |
| `--help` | Show usage |

### What the script does (7 steps)

```
Step 1  Verify project root (CMakeLists.txt present)
Step 2  Check all build dependencies (cmake, gcc, rpmbuild, gtk3, SDL2 …)
Step 3  Initialise / update git submodules
Step 4  Run cmake + make install/strip  →  bin/openboardview
Step 5  Run make package (CPack)        →  *.rpm + *.deb
Step 6  Select newest *.rpm by file timestamp
Step 7  Smoke-test: rpm -qip, rpm -qlp, binary executable check
```

> **Note on newest-package selection:** `ls -t *.rpm | head -n 1` orders by `mtime` descending and takes the first result. If you run the script multiple times (e.g. testing version bumps), the most recently generated package is always used — no manual hunting required.

### Example output (abbreviated)

```
╔══════════════════════════════════════════════╗
║  OpenBoardView — RPM Automated Build Script  ║
╚══════════════════════════════════════════════╝
  Project root : /home/user/OpenBoardView
  Threads      : 8   Recompile: false

══ Step 2 — Checking build dependencies ══
[OK]    cmake found   [OK]    rpmbuild found
[OK]    pkg: gtk+-3.0  [OK]    pkg: sdl2  …

══ Step 6 — Selecting newest RPM by timestamp ══
[OK]    Selected: openboardview-10.0.0-1.aarch64.rpm  (modified: 2026-10-03 00:45:48)

══ Step 7 — Smoke-testing the RPM ══
[OK]    Package name    : openboardview
[OK]    Binary /usr/bin/openboardview confirmed in package payload
[OK]    Smoke test passed

╔══════════════════════════════════════════════════╗
║  Build complete!                                 ║
║  RPM : openboardview-10.0.0-1.aarch64.rpm        ║
║  Size: 804K (disk)                               ║
╚══════════════════════════════════════════════════╝
```

---

## System Requirements

| Requirement | Minimum Version |
|---|---|
| OS | Fedora 38+ / RHEL 9+ / any RPM-based distro |
| Architecture | x86_64 **or** aarch64 (ARM64) |
| CMake | 3.11+ |
| GCC / G++ | 4.8+ (C++11 support required) |
| rpm-build | Any recent version |
| Git | 2.x+ |

> **Note:** This guide was tested on **Fedora Linux Asahi Remix 44 (aarch64)** with CMake 4.3.0 and GCC 16.2.1. The resulting package `openboardview-10.0.0-1.aarch64.rpm` is ~804 KB (1.78 MB installed).

---

## Install Build Dependencies

### Fedora / RHEL / CentOS Stream

```bash
sudo dnf install -y \
  cmake \
  gcc \
  gcc-c++ \
  make \
  git \
  rpm-build \
  gtk3-devel \
  SDL2-devel \
  sqlite-devel \
  fontconfig-devel \
  zlib-devel \
  python3-jinja2
```

### Verify all libraries are detected

```bash
pkg-config --exists gtk+-3.0  && echo "gtk3 ✓"
pkg-config --exists sdl2      && echo "SDL2 ✓"
pkg-config --exists sqlite3   && echo "sqlite3 ✓"
pkg-config --exists fontconfig && echo "fontconfig ✓"
pkg-config --exists zlib      && echo "zlib ✓"
```

All five should print a checkmark. If any are missing, install the corresponding `-devel` package.

---

## Clone the Repository

```bash
git clone https://github.com/akbar-npj/OpenBoardView.git
cd OpenBoardView
```

> **Important:** Always clone with full history (not `--depth 1`) so the build system can embed the correct git revision string into the binary.

---

## Initialize Git Submodules

OpenBoardView bundles several third-party libraries as git submodules:

| Submodule | Purpose |
|---|---|
| `src/imgui` | Immediate-mode GUI framework |
| `src/glad` | OpenGL loader |
| `src/zlib` | Compression library |
| `src/stb` | Image loading (stb_image) |
| `src/utf8` | UTF-8 string utilities |
| `src/filesystem` | `std::filesystem` polyfill |
| `src/mpc` | Parser combinator library |

```bash
git submodule update --init --recursive
```

This step clones all submodules from their upstream GitHub repositories. It requires internet access and may take 1–3 minutes depending on connection speed.

---

## Manual Build Steps

> If you prefer to use the automated script, skip directly to [Generate the RPM Package](#generate-the-rpm-package).

### Option A — Using `build.sh` (upstream wrapper)

```bash
bash ./build.sh --recompile
```

`build.sh` handles cmake configuration and `make install/strip` in one step. It installs the binary and assets under `bin/` and `share/` in the project root.

| Flag | Description |
|---|---|
| `--recompile` | Delete `release_build/` and start fresh |
| `--debug` | Debug build (uses `debug_build/`, no stripping) |
| `--help` | Show usage |

### Option B — Manual CMake

```bash
mkdir release_build && cd release_build
export DESTDIR="$(dirname $PWD)"   # install into project root
cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX= ..
make -j$(nproc) install/strip
```

### Expected installed files

```
bin/openboardview                              ← executable
share/applications/openboardview.desktop      ← .desktop entry
share/icons/hicolor/scalable/apps/openboardview.svg
share/mime/packages/openboardview.xml
share/metainfo/openboardview.appdata.xml
```

---

## Generate the RPM Package

```bash
cd release_build
make package
```

CPack reads the packaging configuration from `CMakeLists.txt` and calls `rpmbuild` internally. It generates **both** packages simultaneously:

```
CPack: Create package using DEB → openboardview_10.0.0-1_arm64.deb
CPack: Create package using RPM → openboardview-10.0.0-1.aarch64.rpm
```

Both files are placed in the **project root** (`/path/to/OpenBoardView/`).

### Selecting the newest RPM

If you have run the build multiple times, always pick the latest package by timestamp:

```bash
# Newest RPM — reliable one-liner used by rpm_package_build.sh
NEWEST_RPM=$(ls -t *.rpm | head -n 1)
echo "Selected: $NEWEST_RPM"
```

### Package details

| Field | Value |
|---|---|
| Package name | `openboardview` |
| Version | `10.0.0` |
| Release | `1` |
| Architecture | `aarch64` |
| License | MIT |
| Group | Applications/Engineering |
| Installed size | ~1.78 MB |
| RPM size | ~804 KB |
| Requires | `gtk3` |

### Inspect the package without installing

```bash
# List package metadata
rpm -qip openboardview-10.0.0-1.aarch64.rpm

# List files included in the package
rpm -qlp openboardview-10.0.0-1.aarch64.rpm
```

---

## Install the RPM

```bash
# Using dnf (recommended — resolves dependencies automatically)
sudo dnf localinstall openboardview-10.0.0-1.aarch64.rpm

# Or using rpm directly
sudo rpm -ivh openboardview-10.0.0-1.aarch64.rpm
```

### Verify installation

```bash
rpm -q openboardview
which openboardview
```

### Uninstall

```bash
sudo dnf remove openboardview
# or
sudo rpm -e openboardview
```

---

## Package Contents

The RPM installs the following files:

```
/usr/bin/openboardview                                    ← main executable
/usr/share/applications/openboardview.desktop            ← app menu entry
/usr/share/icons/hicolor/scalable/apps/openboardview.svg ← app icon
/usr/share/metainfo/openboardview.appdata.xml            ← AppStream metadata
/usr/share/mime/packages/openboardview.xml               ← MIME type associations
```

Post-install scripts automatically refresh the icon cache, MIME database, and desktop database.

---

## Troubleshooting

### CMake can't find SDL2
```bash
sudo dnf install SDL2-devel
```

### CMake can't find GTK3
```bash
sudo dnf install gtk3-devel
```

### `rpmbuild` not found
```bash
sudo dnf install rpm-build
```

### `make install/strip` fails with "cannot create directory: /share/applications"

This means `DESTDIR` was not set. The build assumes files are staged into the project root. Always use the script or set `DESTDIR` explicitly:

```bash
export DESTDIR="/path/to/OpenBoardView"
# then re-run make install/strip
```

Or simply use `rpm_package_build.sh` which handles this automatically.

### Submodule clone fails (SSL / network error)

Try using SSH instead of HTTPS:
```bash
git config --global url."git@github.com:".insteadOf "https://github.com/"
git submodule update --init --recursive
```

### Build fails with "GCC version needs to be >= 4.8"
```bash
sudo dnf install gcc gcc-c++
```

### `make package` produces no `.rpm`

Ensure `rpm-build` is installed **before** running CMake. If CMake was already run without it, start fresh:

```bash
rm -rf release_build
bash rpm_package_build.sh --recompile
```

---

## CI/CD Reference

The project's GitHub Actions workflow (`.github/workflows/make_packages.yml`) uses Docker to build the DEB and RPM packages on every push. The Docker-based build environment is defined in `Dockerfile`.

To replicate the CI build locally using Docker:

```bash
docker build --target linux-build-env -t openboardview.org/linux-build-env:latest .
docker run --rm -v "$PWD:$PWD" -w "$PWD" -u "$(id -u):$(id -g)" \
  openboardview.org/linux-build-env:latest \
  bash rpm_package_build.sh --recompile
```

---

## Quick Reference

```bash
# Automated (recommended)
git clone https://github.com/akbar-npj/OpenBoardView.git
cd OpenBoardView
bash rpm_package_build.sh --recompile

# Manual
git clone https://github.com/akbar-npj/OpenBoardView.git
cd OpenBoardView
git submodule update --init --recursive
bash ./build.sh --recompile
cd release_build && make package
ls -t ../*.rpm | head -n 1   # newest RPM
```

---

*Guide generated for OpenBoardView v10.0.0 on Fedora Linux Asahi Remix 44 (aarch64)*  
*Automated build script: [`rpm_package_build.sh`](./rpm_package_build.sh)*
