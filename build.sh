#!/usr/bin/env bash

set -e

ZIG_VERSION_FILE=".zigversion"
DEFAULT_ZIG_VERSION="0.14"
ZIG_DIR=".zig-install"
ZIG_BIN=""
FORCE_MODE=false
DOWNLOAD_MODE=false

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -d|--download)
            DOWNLOAD_MODE=true
            shift
            ;;
        *)
            # Unknown option
            ;;
    esac
done

# Function to check if two version strings are compatible
check_version_compatibility() {
    local system_version="$1"
    local expected_version="$2"
    
    # Extract major.minor from versions (ignore patch and build info)
    local sys_major_minor=$(echo "$system_version" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
    local exp_major_minor=$(echo "$expected_version" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
    
    if [ "$sys_major_minor" = "$exp_major_minor" ]; then
        return 0  # Compatible
    else
        return 1  # Not compatible
    fi
}

# If download mode is enabled, skip system zig and force download
if [ "$DOWNLOAD_MODE" = true ]; then
    echo "[↓] Download mode enabled (-d/--download), skipping system zig check"
    # Skip to download logic
else
    # First, check for existing local zig installation
    if [ -d "$ZIG_DIR" ] && find "${ZIG_DIR}" -type f -name zig -perm -111 | grep -q .; then
        local_zig_bin=$(find "${ZIG_DIR}" -type f -name zig -perm -111 | head -n 1)
        if [ -n "$local_zig_bin" ]; then
            # Check if local zig version matches .zigversion
            if [ -f "$ZIG_VERSION_FILE" ]; then
                expected_version=$(cat "$ZIG_VERSION_FILE")
                local_version=$("$local_zig_bin" version 2>/dev/null || echo "unknown")
                
                if [ "$local_version" != "unknown" ] && check_version_compatibility "$local_version" "$expected_version"; then
                    echo "[✔] Found compatible local zig installation at $local_zig_bin (version: $local_version)"
                    ZIG_BIN="$local_zig_bin"
                else
                    echo "[!] Local zig at $local_zig_bin has version $local_version, but .zigversion requires $expected_version"
                fi
            else
                echo "[✔] Found local zig installation at $local_zig_bin"
                ZIG_BIN="$local_zig_bin"
            fi
        fi
    fi
    
    # If no compatible local zig found, check system zig
    if [ -z "$ZIG_BIN" ] && command -v zig >/dev/null 2>&1; then
        echo "[✔] Found system 'zig' at: $(command -v zig)"
        system_zig_bin=$(command -v zig)
        
        # Check version compatibility if .zigversion exists
        if [ -f "$ZIG_VERSION_FILE" ]; then
            expected_version=$(cat "$ZIG_VERSION_FILE")
            system_version=$("$system_zig_bin" version 2>/dev/null || echo "unknown")
            
            if [ "$system_version" != "unknown" ]; then
                if check_version_compatibility "$system_version" "$expected_version"; then
                    echo "[✔] System zig version ($system_version) is compatible with expected version ($expected_version)"
                    ZIG_BIN="$system_zig_bin"
                else
                    if [ "$FORCE_MODE" = true ]; then
                        echo "[!] WARNING: System zig version ($system_version) differs from .zigversion ($expected_version)"
                        echo "[!] Force mode enabled (-f/--force), will download and use expected version instead"
                        # Continue to download logic below
                    else
                        echo "[!] WARNING: System zig version ($system_version) differs from .zigversion ($expected_version)"
                        echo "[!] This may cause compatibility issues, but proceeding with system zig anyway"
                        echo "[!] Use -f or --force to download and use the exact version from .zigversion"
                        ZIG_BIN="$system_zig_bin"
                    fi
                fi
            else
                echo "[!] WARNING: Could not determine system zig version, proceeding anyway"
                ZIG_BIN="$system_zig_bin"
            fi
        else
            # No .zigversion file, use system zig
            ZIG_BIN="$system_zig_bin"
        fi
    fi
fi

# If we don't have a zig binary yet (either no system zig, force mode with version mismatch, or download mode)
if [ -z "$ZIG_BIN" ]; then
    echo "[!] Need to download zig binary."

    if [ "$DOWNLOAD_MODE" = false ] && ([ -x "${ZIG_DIR}/zig" ] || [ -x "${ZIG_DIR}"/zig*/zig ]); then
        # Use existing zig from .zig-install
        ZIG_BIN=$(find "${ZIG_DIR}" -type f -name zig -perm -111 | head -n 1)
        echo "[✔] Found existing zig in ${ZIG_BIN}"
    else
        if [ "$DOWNLOAD_MODE" = true ]; then
            echo "[↓] Download mode: Will download fresh copy regardless of existing installation"
        fi
        
        # Prompt user to download zig (skip prompt in download mode)
        if [ "$DOWNLOAD_MODE" = false ]; then
            read -p "Do you want to download Zig as per .zigversion and install to .zig-install/? [Y/n]: " yn
            case $yn in
                [Nn]* ) echo "Aborted."; exit 1;;
                * ) ;;
            esac
        fi

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

        # Clean up temporary download file
        rm -f "/tmp/${ZIG_TAR}"

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

