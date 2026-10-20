#!/bin/zsh
# 打包成 build/Islet-<版本>.dmg：Release 建置後放進 DMG，旁邊附 Applications 捷徑方便拖曳安裝。
# 版本號取自 Resources/Info.plist 的 CFBundleShortVersionString。
#
#   ./scripts/make-dmg.sh
#   SIGN_IDENTITY="Islet Dev" ./scripts/make-dmg.sh   # 用自簽憑證簽章
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

APP_NAME="Islet"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/$APP_NAME-$VERSION.dmg"

CONFIG=release ./scripts/bundle.sh

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "▸ 組裝 DMG 內容"
ditto "build/$APP_NAME.app" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

echo "▸ hdiutil create"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" > /dev/null

echo "✓ $DMG"
