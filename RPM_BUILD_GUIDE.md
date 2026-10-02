# OpenBoardView — RPM Compilation Guide

> **Platform:** Fedora Linux Asahi Remix 44 (aarch64 / Apple Silicon)  
> **Package:** `openboardview-10.0.0-1.aarch64.rpm`  
> **Build Date:** 2026-10-03  
> **Build System:** CMake + CPack + rpmbuild

---

## Table of Contents

1. [Overview](#overview)
2. [System Requirements](#system-requirements)
3. [Install Build Dependencies](#install-build-dependencies)
4. [Clone the Repository](#clone-the-repository)
5. [Initialize Git Submodules](#initialize-git-submodules)
6. [Build the Project](#build-the-project)
7. [Generate the RPM Package](#generate-the-rpm-package)
8. [Install the RPM](#install-the-rpm)
9. [Package Contents](#package-contents)
10. [Troubleshooting](#troubleshooting)
11. [CI/CD Reference](#cicd-reference)

---

## Overview

OpenBoardView is an open-source viewer for PCB board layout files (`.brd`, `.bvr`, `.obv`, etc.). It uses **CMake** as its build system and **CPack** to generate distribution packages. On Linux, CPack produces both `.deb` (Debian/Ubuntu) and `.rpm` (Fedora/RHEL/openSUSE) packages in a single `make package` step.

```
Source → cmake → make → make package → .rpm + .deb
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

> **Note:** This guide was tested on **Fedora Linux Asahi Remix 44 (aarch64)** with CMake 4.3.0 and GCC 16.2.1. The resulting package `openboardview-10.0.0-1.aarch64.rpm` is ~803 KB (1.78 MB installed).

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
pkg-config --exists gtk+-3.0 && echo "gtk3 ✓"
pkg-config --exists sdl2     && echo "SDL2 ✓"
pkg-config --exists sqlite3  && echo "sqlite3 ✓"
pkg-config --exists fontconfig && echo "fontconfig ✓"
pkg-config --exists zlib     && echo "zlib ✓"
```

All five should print a checkmark. If any are missing, install the corresponding `-devel` package.

---

## Clone the Repository

```bash
git clone https://github.com/akbar-npj/OpenBoardView.git
cd OpenBoardView
```

> **Important:** Always clone with full history (`--no shallow`) so the build system can embed the correct git revision string into the binary.

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

## Build the Project

Use the provided `build.sh` wrapper script which handles CMake configuration and `make install/strip` in one step:

```bash
bash ./build.sh --recompile
```

### What `build.sh` does

1. Creates a `release_build/` directory (or wipes it if `--recompile` is passed)
2. Runs `cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX= ..`
3. Runs `make -j$(nproc) install/strip` — compiles with all CPU threads and strips debug symbols

### Optional flags

| Flag | Description |
|---|---|
| `--recompile` | Delete `release_build/` and start fresh |
| `--debug` | Debug build (uses `debug_build/`, no stripping) |
| `--help` | Show usage |

### Manual CMake approach (alternative)

```bash
mkdir release_build && cd release_build
cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX= ..
make -j$(nproc) install/strip
```

### Expected output

Upon success, the binary and assets are installed to:

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
| RPM size | ~803 KB |
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
sudo rpm -ivh openboardview-10.0.0-1.aarch64.rpm
```

Or using `dnf` for automatic dependency resolution:

```bash
sudo dnf localinstall openboardview-10.0.0-1.aarch64.rpm
```

### Verify installation

```bash
rpm -q openboardview
openboardview --version   # or just launch it
```

### Uninstall

```bash
sudo rpm -e openboardview
# or
sudo dnf remove openboardview
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

### Submodule clone fails (SSL / network error)

Try using SSH instead of HTTPS for cloning:
```bash
git config --global url."git@github.com:".insteadOf "https://github.com/"
git submodule update --init --recursive
```

### Build fails with "GCC version needs to be >= 4.8"

Update GCC:
```bash
sudo dnf install gcc gcc-c++
```

### `make package` produces no `.rpm`

Ensure `rpm-build` is installed before running CMake. If CMake was already run without it, re-run from scratch:

```bash
rm -rf release_build
bash ./build.sh --recompile
cd release_build && make package
```

---

## CI/CD Reference

The project's GitHub Actions workflow (`.github/workflows/make_packages.yml`) uses Docker to build the DEB and RPM packages on every push. The Docker-based build environment is defined in `Dockerfile` and uses a Debian base image for cross-compatibility.

To replicate the CI build locally using Docker:

```bash
docker build --target linux-build-env -t openboardview.org/linux-build-env:latest .
docker run --rm -v "$PWD:$PWD" -w "$PWD" -u "$(id -u):$(id -g)" \
  openboardview.org/linux-build-env:latest \
  sh -c 'bash ./build.sh --recompile && cd release_build && make package'
```

---

## Quick Reference

```bash
# Full build + RPM in one shot
git clone https://github.com/akbar-npj/OpenBoardView.git
cd OpenBoardView
git submodule update --init --recursive
bash ./build.sh --recompile
cd release_build && make package
ls ../*.rpm
```

---

*Guide generated for OpenBoardView v10.0.0 on Fedora Linux Asahi Remix 44 (aarch64)*
