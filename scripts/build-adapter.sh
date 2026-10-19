#!/bin/zsh
# 不用 CMake，直接用 clang 把 vendored mediaremote-adapter 編成：
#   build/adapter/MediaRemoteAdapter.framework   （由系統的 /usr/bin/perl 載入）
#   build/adapter/MediaRemoteAdapterTestClient   （`test` 指令在沒有東西播放時用來確認 adapter 還能用）
# 編譯參數對照 Vendor/mediaremote-adapter/CMakeLists.txt。
set -euo pipefail

ROOT="${0:A:h:h}"
SRC="$ROOT/Vendor/mediaremote-adapter"
OUT="$ROOT/build/adapter"
FRAMEWORK="$OUT/MediaRemoteAdapter.framework"
STAMP="$OUT/.stamp"
COMMON=(-arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -O2)

# 原始碼沒變就不重編
if [[ -f "$STAMP" && -f "$FRAMEWORK/Versions/A/MediaRemoteAdapter" && -f "$OUT/MediaRemoteAdapterTestClient" ]] \
  && [[ -z "$(find "$SRC/src" "$SRC/include" "$0" -newer "$STAMP" -print -quit)" ]]; then
  exit 0
fi

rm -rf "$OUT"
mkdir -p "$FRAMEWORK/Versions/A/Resources" "$FRAMEWORK/Versions/A/Headers"

echo "▸ 編譯 MediaRemoteAdapter.framework"
clang "${COMMON[@]}" -dynamiclib -fvisibility=default \
  -I "$SRC/include" -I "$SRC/src" \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -current_version 0.1.0 -compatibility_version 0.1.0 \
  "$SRC"/src/adapter/*.m "$SRC"/src/private/MediaRemote.m "$SRC"/src/utility/*.m \
  -o "$FRAMEWORK/Versions/A/MediaRemoteAdapter"

cp "$SRC/include/MediaRemoteAdapter.h" "$FRAMEWORK/Versions/A/Headers/"
cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>MediaRemoteAdapter</string>
	<key>CFBundleIdentifier</key>
	<string>com.vandenbe.MediaRemoteAdapter</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>MediaRemoteAdapter</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>0.1.0</string>
</dict>
</plist>
PLIST
ln -s A "$FRAMEWORK/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FRAMEWORK/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"
ln -s Versions/Current/Headers "$FRAMEWORK/Headers"

echo "▸ 編譯 MediaRemoteAdapterTestClient"
clang "${COMMON[@]}" -I "$SRC/src/test" \
  -framework Foundation -framework MediaPlayer \
  "$SRC"/src/test/main.m "$SRC"/src/test/NowPlayingTest.m \
  -o "$OUT/MediaRemoteAdapterTestClient"

touch "$STAMP"
