#!/usr/bin/env bash

set -e

ZIG_VERSION_FILE=".zigversion"
DEFAULT_ZIG_VERSION="0.14"
ZIG_DIR=".zig-install"
ZIG_BIN=""

# Check for system zig
if command -v zig >/dev/null 2>&1; then
    echo "[✔] Found system 'zig' at: $(command -v zig)"
    ZIG_BIN=$(command -v zig)
else
    echo "[!] 'zig' binary not found in system PATH."

    if [ -x "${ZIG_DIR}/zig" ] || [ -x "${ZIG_DIR}"/zig*/zig ]; then
        # Use existing zig from .zig-install
        ZIG_BIN=$(find "${ZIG_DIR}" -type f -name zig -perm -111 | head -n 1)
        echo "[✔] Found existing zig in ${ZIG_BIN}"
    else
        # Prompt user to download zig
        read -p "Do you want to download Zig as per .zigversion and install to .zig-install/? [Y/n]: " yn
        case $yn in
            [Nn]* ) echo "Aborted."; exit 1;;
            * ) ;;
        esac

        if [ ! -f "$ZIG_VERSION_FILE" ]; then
            echo "[✘] $ZIG_VERSION_FILE not found! Defaulting to zig ${DEFAULT_ZIG_VERSION} (set DEFAULT_ZIG_VERSION in build.sh to change)"
            ZIG_VERSION="${DEFAULT_ZIG_VERSION}"
        else
            ZIG_VERSION=$(cat "$ZIG_VERSION_FILE")
        fi
        echo "[→] Zig version to download: $ZIG_VERSION"

        # Detect platform
        UNAME=$(uname -s)
        ARCH=$(uname -m)
        PLATFORM=""
        EXT="tar.xz"

        case "$UNAME" in
            Linux)
                PLATFORM="linux"
                ;;
            Darwin)
                PLATFORM="macos"
                ;;
            MINGW*|MSYS*|CYGWIN*)
                PLATFORM="windows"
                EXT="zip"
                ;;
            *)
                echo "[✘] Unsupported OS: $UNAME"
                exit 1
                ;;
        esac

        case "$ARCH" in
            x86_64)
                ARCH="x86_64"
                ;;
            aarch64|arm64)
                ARCH="aarch64"
                ;;
            armv7l|armv7a)
                ARCH="armv7a"
                ;;
            riscv64)
                ARCH="riscv64"
                ;;
            ppc64le|powerpc64le)
                ARCH="powerpc64le"
                ;;
            i386|i686|x86)
                ARCH="x86"
                ;;
            loongarch64)
                ARCH="loongarch64"
                ;;
            s390x)
                ARCH="s390x"
                ;;
            *)
                echo "[✘] Unsupported architecture: $ARCH"
                echo "[!] Supported architectures: x86_64, aarch64, armv7a, riscv64, powerpc64le, x86, loongarch64, s390x"
                exit 1
                ;;
        esac

        ZIG_TAR="zig-${ARCH}-${PLATFORM}-${ZIG_VERSION}.${EXT}"
        ZIG_URL="https://ziglang.org/download/${ZIG_VERSION}/${ZIG_TAR}"

        echo "[↓] Downloading Zig from $ZIG_URL..."
        mkdir -p "$ZIG_DIR"
        
        # Download with better error handling
        if ! curl -L --fail "$ZIG_URL" -o "/tmp/${ZIG_TAR}"; then
            echo "[✘] Download failed. Let's try the master builds URL instead..."
            ZIG_URL="https://ziglang.org/builds/${ZIG_TAR}"
            echo "[↓] Trying: $ZIG_URL"
            if ! curl -L --fail "$ZIG_URL" -o "/tmp/${ZIG_TAR}"; then
                echo "[✘] Both download URLs failed. Please check the Zig version in .zigversion"
                echo "[!] Available versions: https://ziglang.org/download/"
                exit 1
            fi
        fi
        
        # Verify the downloaded file is actually a tar archive
        if ! file "/tmp/${ZIG_TAR}" | grep -q "archive\|compressed"; then
            echo "[✘] Downloaded file is not a valid archive:"
            file "/tmp/${ZIG_TAR}"
            echo "[!] File contents (first 200 bytes):"
            head -c 200 "/tmp/${ZIG_TAR}"
            echo
            exit 1
        fi

        echo "[⇩] Extracting Zig..."
        if [[ "$EXT" == "zip" ]]; then
            unzip "/tmp/${ZIG_TAR}" -d "$ZIG_DIR"
        else
            tar -xf "/tmp/${ZIG_TAR}" -C "$ZIG_DIR"
        fi

        ZIG_BIN=$(find "${ZIG_DIR}" -type f -name zig -perm -111 | head -n 1)

        if [ ! -x "$ZIG_BIN" ]; then
            echo "[✘] Failed to find 'zig' binary after extraction."
            exit 1
        fi

        echo "[✔] Zig installed to $ZIG_BIN"
    fi
fi

# Build loxz
echo "[⚙] Building loxz with $ZIG_BIN..."
"$ZIG_BIN" build -Doptimize=ReleaseFast

# Move built binary
BUILT_BIN="./zig-out/bin/loxz"
if [ ! -f "$BUILT_BIN" ]; then
    echo "[✘] Build failed, binary not found at $BUILT_BIN"
    exit 1
fi

cp "$BUILT_BIN" ./loxz
echo "[✔] loxz built and copied to ./loxz"

