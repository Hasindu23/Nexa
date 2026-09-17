#!/bin/bash
set -euo pipefail
NEXA_ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
NEXA_APP="${TARGET_BUILD_DIR:?}/${WRAPPER_NAME:?}"
NEXA_VENDOR="$NEXA_ROOT/ThirdParty/mediaremote-adapter"
NEXA_FRAMEWORK="$NEXA_APP/Contents/Frameworks/MediaRemoteAdapter.framework"
mkdir -p "$NEXA_FRAMEWORK/Versions/A/Resources" "$NEXA_APP/Contents/Resources"
/usr/bin/xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -O2 -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 \
  -I "$NEXA_VENDOR/include" -I "$NEXA_VENDOR/src" \
  "$NEXA_VENDOR"/src/adapter/*.m "$NEXA_VENDOR"/src/private/*.m "$NEXA_VENDOR"/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name '@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter' \
  -o "$NEXA_FRAMEWORK/Versions/A/MediaRemoteAdapter"
cat > "$NEXA_FRAMEWORK/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>app.nexa.MediaRemoteAdapter</string><key>CFBundleExecutable</key><string>MediaRemoteAdapter</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleVersion</key><string>1</string></dict></plist>
PLIST
ln -sfn A "$NEXA_FRAMEWORK/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$NEXA_FRAMEWORK/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$NEXA_FRAMEWORK/Resources"
cp "$NEXA_VENDOR/mediaremote-adapter.pl" "$NEXA_APP/Contents/Resources/"
cp "$NEXA_VENDOR/LICENSE" "$NEXA_APP/Contents/Resources/MediaRemoteAdapter-LICENSE.txt"
/usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$NEXA_FRAMEWORK"
