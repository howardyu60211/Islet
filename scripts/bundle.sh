#!/bin/zsh
# 組出 build/Islet.app：編譯 Swift、放入 Info.plist／圖示／Sparkle／MediaRemoteAdapter，最後簽章。
#
#   CONFIG=debug ./scripts/bundle.sh               # Debug 建置（含「模擬事件」選單）
#   SIGN_IDENTITY="Islet Dev" ./scripts/bundle.sh   # 用自簽憑證簽章，權限不會每次重問
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP_NAME="Islet"
APP="build/$APP_NAME.app"
CONTENTS="$APP/Contents"

echo "▸ swift build ($CONFIG)"
swift build -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ 組裝 $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
fi
# 各語言的 App 名稱與權限說明（InfoPlist.strings）
for lproj in Resources/*.lproj(N); do
  ditto "$lproj" "$CONTENTS/Resources/${lproj:t}"
done

# 自動更新用的 Sparkle（SwiftPM 會把它放在 bin 資料夾，App 裡要放到 Frameworks 並加上對應的 rpath）
mkdir -p "$CONTENTS/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/$APP_NAME"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$CONTENTS/Resources/Sparkle-LICENSE.txt"

# 全系統「正在播放」用的 mediaremote-adapter（沒有 vendored 原始碼時略過，App 會退回 Music/Spotify 模式）
if [[ -d Vendor/mediaremote-adapter ]]; then
  ./scripts/build-adapter.sh
  mkdir -p "$CONTENTS/Frameworks" "$CONTENTS/Helpers"
  ditto build/adapter/MediaRemoteAdapter.framework "$CONTENTS/Frameworks/MediaRemoteAdapter.framework"
  cp build/adapter/MediaRemoteAdapterTestClient "$CONTENTS/Helpers/MediaRemoteAdapterTestClient"
  cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$CONTENTS/Resources/mediaremote-adapter.pl"
  cp Vendor/mediaremote-adapter/LICENSE "$CONTENTS/Resources/mediaremote-adapter-LICENSE.txt"
fi

echo "▸ codesign（$SIGN_IDENTITY）"
# 先簽裡面的程式碼，最後才簽整個 App
if [[ -d "$CONTENTS/Helpers" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$CONTENTS/Helpers/MediaRemoteAdapterTestClient"
fi
# Sparkle 裡的程式由內而外各自簽（不用 --deep，它會弄壞 XPC service 的 entitlements）
SPARKLE="$CONTENTS/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign "$SIGN_IDENTITY" "$SPARKLE/XPCServices/Installer.xpc"
codesign --force --sign "$SIGN_IDENTITY" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
codesign --force --sign "$SIGN_IDENTITY" "$SPARKLE/Autoupdate"
codesign --force --sign "$SIGN_IDENTITY" "$SPARKLE/Updater.app"
codesign --force --sign "$SIGN_IDENTITY" "$CONTENTS/Frameworks/Sparkle.framework"
if [[ -d "$CONTENTS/Frameworks/MediaRemoteAdapter.framework" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$CONTENTS/Frameworks/MediaRemoteAdapter.framework"
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "✓ $APP"
