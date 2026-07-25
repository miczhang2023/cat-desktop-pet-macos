#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="小橘桌宠"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
EXECUTABLE="CatDesktopPet"
MIN_MACOS="12.0"
APP_VERSION="2.0.1"
BUILD_VERSION="3"

rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR/tools" "$BUILD_DIR/assets" "$MACOS_DIR" "$RESOURCES_DIR"

swiftc -swift-version 5 \
  "$PROJECT_DIR/Tools/prepare_assets.swift" \
  -o "$BUILD_DIR/tools/prepare_assets" \
  -framework AppKit

"$BUILD_DIR/tools/prepare_assets" \
  "$PROJECT_DIR/Resources/cat-open.png" \
  "$PROJECT_DIR/Resources/cat-blink.png" \
  "$BUILD_DIR/assets"

ARCH_BINARIES=()
for ARCH in arm64 x86_64; do
  OUTPUT="$BUILD_DIR/$EXECUTABLE-$ARCH"
  if swiftc -swift-version 5 \
    -O \
    -target "$ARCH-apple-macosx$MIN_MACOS" \
    "$PROJECT_DIR"/Sources/*.swift \
    -o "$OUTPUT" \
    -framework AppKit \
    -framework QuartzCore \
    -framework ServiceManagement 2>"$BUILD_DIR/swiftc-$ARCH.log"; then
    ARCH_BINARIES+=("$OUTPUT")
  else
    print "Skipping $ARCH build; see $BUILD_DIR/swiftc-$ARCH.log"
  fi
done

if (( ${#ARCH_BINARIES[@]} == 0 )); then
  print "No architecture could be built."
  exit 1
elif (( ${#ARCH_BINARIES[@]} == 1 )); then
  cp "${ARCH_BINARIES[1]}" "$MACOS_DIR/$EXECUTABLE"
else
  lipo -create "${ARCH_BINARIES[@]}" -output "$MACOS_DIR/$EXECUTABLE"
fi

cp "$PROJECT_DIR/Resources/cat-open.png" "$RESOURCES_DIR/cat-open.png"
cp "$BUILD_DIR/assets/cat-eyes-blink.png" "$RESOURCES_DIR/cat-eyes-blink.png"
cp "$BUILD_DIR/assets/AppIcon-1024.png" "$RESOURCES_DIR/AppIcon-1024.png"
mkdir -p "$RESOURCES_DIR/Directions"
for DIRECTION in left right up down up-left up-right down-left down-right; do
  cp "$PROJECT_DIR/Resources/Directions/cat-$DIRECTION.png" \
    "$RESOURCES_DIR/Directions/cat-$DIRECTION.png"
done

ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for SPEC in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"; do
  SIZE="${SPEC%% *}"
  NAME="${SPEC#* }"
  sips -z "$SIZE" "$SIZE" "$BUILD_DIR/assets/AppIcon-1024.png" \
    --out "$ICONSET/$NAME" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.stephen.cat-desktop-pet</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

chmod +x "$MACOS_DIR/$EXECUTABLE"
codesign --force --deep --sign - "$APP_BUNDLE"

print "$APP_BUNDLE"
