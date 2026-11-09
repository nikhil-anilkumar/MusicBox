#!/bin/bash
# Builds MusicBox.ipa for iOS 6+ (armv7) on Linux.
# Needs: the Theos Linux iOS toolchain (clang + ld64 + ldid) and an iOS SDK with armv7 stubs.
set -euo pipefail
cd "$(dirname "$0")"

TOOLCHAIN=${TOOLCHAIN:-../toolchain/tc/linux/iphone/bin}
SDK=${SDK:-../toolchain/sdk/iPhoneOS9.3.sdk}
BUILD=build
APP=$BUILD/Payload/MusicBox.app

CFLAGS=(-target armv7-apple-ios6.0 -miphoneos-version-min=6.0 -isysroot "$SDK" -O2 -g0 -IVendor
        -Wno-deprecated-declarations -Wno-nullability-completeness)

rm -rf "$BUILD"; mkdir -p "$BUILD/obj" "$APP"

echo "== compile"
"$TOOLCHAIN/clang" "${CFLAGS[@]}" -w -c Vendor/decoders.c -o "$BUILD/obj/decoders.o"
for src in Sources/*.m; do
  "$TOOLCHAIN/clang" "${CFLAGS[@]}" -fobjc-arc -Wall -c "$src" -o "$BUILD/obj/$(basename "$src" .m).o"
done

echo "== link"
# (no -fobjc-arc here: it would pull in libarclite, which iOS 6+ does not need)
"$TOOLCHAIN/clang" "${CFLAGS[@]}" "$BUILD"/obj/*.o -o "$APP/MusicBox" \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
  -framework AVFoundation -framework AudioToolbox -framework CoreMedia -framework MediaPlayer

echo "== bundle"
cp Resources/Info.plist Resources/*.png "$APP/"
printf 'APPL????' > "$APP/PkgInfo"
"$TOOLCHAIN/ldid" -Hsha1 -S "$APP/MusicBox"   # fake-sign, SHA-1 only (iOS 6 predates SHA-256 signatures)

(cd "$BUILD" && rm -f ../MusicBox.ipa && zip -qr ../MusicBox.ipa Payload)
echo "== built MusicBox.ipa ($(du -h MusicBox.ipa | cut -f1))"
