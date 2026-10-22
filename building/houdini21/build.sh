#!/usr/bin/env bash
# Builds OpenMoonRay for Houdini 21 on EL9, from nothing to an installed,
# Houdini-ready prefix. See README.md for the why; this file is the how.
#
#   building/houdini21/build.sh --prefix /groups/sandwich/06_software/openmoonray/<name>
#
# Re-running is safe: finished stages are skipped by CMake/make.
set -euo pipefail

# Run in a scrubbed environment. Inherited LD_LIBRARY_PATH, *_DIR/*_ROOT
# hints or a PATH with another Houdini on it change what gets linked
# (GNU ld even consults LD_LIBRARY_PATH for indirect dependencies).
if [[ -z "${OMR_CLEAN_ENV:-}" ]]; then
    exec env -i OMR_CLEAN_ENV=1 HOME="$HOME" USER="$USER" LOGNAME="${LOGNAME:-$USER}" \
        PATH=/usr/bin:/bin LANG=C.UTF-8 TERM="${TERM:-dumb}" TMPDIR="${TMPDIR:-/tmp}" \
        bash "$0" "$@"
fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$(cd "$HERE/../.." && pwd)"

HFS=/opt/hfs21.0.596
PREFIX=""
WORK="${TMPDIR:-/tmp}/openmoonray-build-$USER"
JOBS="$(nproc)"
STAGES="deps moonray post"

CMAKE_VERSION=3.31.6
CMAKE_SHA256=5a1133ff103c71eb5120e2cc3de922733e7d8a26a98ae716397e8676adb367bf
GCC_MAJOR=11   # Houdini 21 is built with GCC 11; libstdc++ must match.

usage() {
    cat <<EOF
Usage: $0 --prefix DIR [--hfs DIR] [--work DIR] [--jobs N] [--stages "deps moonray post"]

  --prefix  Install location (required). Bake the MoonRay and Houdini
            versions into the name; installs are not relocatable.
  --hfs     Houdini install root (default: $HFS)
  --work    Scratch space for downloads and build trees; use a local disk
            (default: $WORK)
  --jobs    Parallel jobs (default: $JOBS)
  --stages  Subset of stages to run (default: "$STAGES")
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --hfs)    HFS="$2"; shift 2 ;;
        --work)   WORK="$2"; shift 2 ;;
        --jobs)   JOBS="$2"; shift 2 ;;
        --stages) STAGES="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

die() { echo "ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[[ -n "$PREFIX" ]] || { usage >&2; die "--prefix is required"; }
[[ -f "$HFS/toolkit/include/SYS/SYS_Version.h" ]] || die "No Houdini at --hfs $HFS"
HOUDINI_VERSION="$(sed -n 's/^#define SYS_VERSION_FULL "\(.*\)"/\1/p' "$HFS/toolkit/include/SYS/SYS_Version.h")"

gcc_major="$(gcc -dumpversion | cut -d. -f1)"
[[ "$gcc_major" == "$GCC_MAJOR" ]] || die "Need GCC $GCC_MAJOR (Houdini's ABI); found $(gcc -dumpversion)"

# Uninitialised or out-of-date submodules silently produce a different build.
if git -C "$SOURCE" submodule status --recursive | grep -q '^[-+U]'; then
    git -C "$SOURCE" submodule status --recursive | grep '^[-+U]' >&2
    die "Submodules above are missing or not at the recorded commit. Run: git submodule update --init --recursive"
fi

DEPS="$PREFIX/deps"
BUILD="$WORK/build"
mkdir -p "$WORK/tools" "$BUILD" "$PREFIX"

# ---------------------------------------------------------------- cmake
CMAKE_DIR="$WORK/tools/cmake-$CMAKE_VERSION-linux-x86_64"
if [[ ! -x "$CMAKE_DIR/bin/cmake" ]]; then
    step "Fetching CMake $CMAKE_VERSION"
    tarball="$WORK/tools/cmake-$CMAKE_VERSION.tar.gz"
    curl -fsSL -o "$tarball" \
        "https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-linux-x86_64.tar.gz"
    echo "$CMAKE_SHA256  $tarball" | sha256sum -c --quiet
    tar xzf "$tarball" -C "$WORK/tools"
fi
CMAKE="$CMAKE_DIR/bin/cmake"

has_stage() { [[ " $STAGES " == *" $1 "* ]]; }

# ----------------------------------------------------------------- deps
if has_stage deps; then
    step "Building dependencies into $DEPS"
    "$CMAKE" -S "$HERE/deps" -B "$BUILD/deps" \
        -DHFS="$HFS" -DInstallRoot="$DEPS" -DDownloadDir="$WORK/downloads"
    "$CMAKE" --build "$BUILD/deps" -j "$JOBS"
fi

# --------------------------------------------------------------- moonray
if has_stage moonray; then
    step "Building OpenMoonRay into $PREFIX"
    # -D before -C: cmake applies them in order and moonray.cmake reads these.
    "$CMAKE" -S "$SOURCE" -B "$BUILD/moonray" -G "Unix Makefiles" \
        -DHFS="$HFS" -DOMR_DEPS="$DEPS" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -C "$HERE/moonray.cmake"
    "$CMAKE" --build "$BUILD/moonray" -j "$JOBS"
    "$CMAKE" --install "$BUILD/moonray"
fi

# ------------------------------------------------------------------ post
if has_stage post; then
    step "Generating shader descriptions and the Houdini package"

    # The Sdr discovery plugin and Houdini UI read one JSON per shader class.
    # Upstream's setup.sh writes these on first use, which a read-only
    # shared install can't do, so generate them now. Trailing slash required.
    rm -rf "$PREFIX/shader_json"
    mkdir -p "$PREFIX/shader_json"
    RDL2_DSO_PATH="$PREFIX/rdl2dso" "$PREFIX/bin/rdl2_json_exporter" \
        --out "$PREFIX/shader_json/" --sparse

    # Our Houdini additions (MoonRay Material Builder TAB tool).
    cp -r "$HERE/houdini/." "$PREFIX/plugin/houdini/"

    omr_version="$(git -C "$SOURCE" describe --tags --always)"
    mkdir -p "$PREFIX/houdini"
    sed -e "s/@HOUDINI_VERSION@/$HOUDINI_VERSION/" -e "s/@OMR_VERSION@/$omr_version/" \
        "$HERE/moonray_package.json.in" > "$PREFIX/houdini/moonray.json"

    # Every installed ELF must resolve all of its libraries, and only from
    # this prefix, Houdini, or the OS. Anything else means the install
    # depends on the build machine.
    echo "  checking library resolution"
    bad=0
    while IFS= read -r elf; do
        out="$(ldd "$elf" 2>/dev/null)" || continue
        while IFS= read -r line; do
            case "$line" in
                *"not found"*) echo "    $elf: $line"; bad=1 ;;
                *"=> /"*)
                    lib="$(sed -E 's/.*=> ([^ ]+).*/\1/' <<<"$line")"
                    case "$lib" in
                        "$PREFIX"/*|"$HFS"/*|/lib64/*|/usr/lib64/*) ;;
                        *) echo "    $elf: unexpected $lib"; bad=1 ;;
                    esac ;;
            esac
        done <<<"$out"
    done < <(find "$PREFIX" -type f \( -name '*.so*' -o -perm -u+x \) -exec sh -c \
                 'head -c4 "$1" | grep -q ELF && echo "$1"' _ {} \;)
    [[ $bad == 0 ]] || die "Install has unresolved or foreign library dependencies (see above)"

    # Record exactly what went into this install.
    {
        echo "openmoonray: $(git -C "$SOURCE" describe --tags --always --dirty) ($(git -C "$SOURCE" rev-parse HEAD))"
        echo "houdini:     $HOUDINI_VERSION ($HFS)"
        echo "compiler:    $(gcc --version | head -1)"
        echo "built:       $(date -u +%Y-%m-%dT%H:%M:%SZ) by $USER on $(hostname)"
        echo
        echo "submodules:"
        git -C "$SOURCE" submodule status --recursive | sed 's/^/  /'
    } > "$PREFIX/BUILDINFO.txt"
fi

step "Done. Houdini package: $PREFIX/houdini/moonray.json"
