#!/bin/bash
# Downloads the Linux iOS toolchain (the one Theos installs: clang + ld64 + ldid) and the
# iPhoneOS 9.3 SDK into ./toolchain, then patches two gaps in the SDK's library stubs.
# Safe to re-run: existing downloads are kept and patches are applied only once.
set -euo pipefail
cd "$(dirname "$0")/.."

TC_URL=https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-x86_64.tar.xz
SDK_URL=https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS9.3.sdk.tar.xz

mkdir -p toolchain/dl toolchain/tc toolchain/sdk
if [ ! -x toolchain/tc/linux/iphone/bin/clang ]; then
  echo "== downloading toolchain"
  curl -fL -o toolchain/dl/tc.tar.xz "$TC_URL"
  tar -xJf toolchain/dl/tc.tar.xz -C toolchain/tc
fi
SDK=toolchain/sdk/iPhoneOS9.3.sdk
if [ ! -d "$SDK" ]; then
  echo "== downloading SDK"
  curl -fL -o toolchain/dl/sdk.tar.xz "$SDK_URL"
  tar -xJf toolchain/dl/sdk.tar.xz -C toolchain/sdk
fi

# 1. libSystem re-exports liblaunch, but the SDK ships no stub for it.
LAUNCH=$SDK/usr/lib/system/liblaunch.tbd
if [ ! -f "$LAUNCH" ]; then
  echo "== patch: adding liblaunch.tbd"
  cat > "$LAUNCH" <<'EOF'
---
archs:                 [ armv7, armv7s, arm64, i386, x86_64 ]
platform:              ios
install-name:          /usr/lib/system/liblaunch.dylib
current-version:       765.1.1
compatibility-version: 1
exports:
  - archs:              [ armv7, armv7s, arm64, i386, x86_64 ]
    symbols:            [ _launch_data_alloc, _launch_msg ]
...
EOF
fi

# 2. memcpy/memset/... are missing from the stubs. They bind through libSystem at runtime,
#    so which sub-library declares them doesn't matter on the device.
PLATFORM=$SDK/usr/lib/system/libsystem_platform.tbd
if ! grep -q " _memcpy," "$PLATFORM"; then
  echo "== patch: adding memcpy & co. to libsystem_platform.tbd"
  sed -i '0,/__platform_bzero,/s//__platform_bzero, _bzero, _memcmp, _memcpy, _memmove, _memset, _memchr, _memccpy,/' "$PLATFORM"
fi

echo "== toolchain ready"
