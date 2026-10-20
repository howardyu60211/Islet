#!/bin/zsh
# 發佈新版本：改版本號 → 打包 DMG → 產生附 EdDSA 簽章的 appcast.xml → commit 與 tag → 推上 GitHub 並建立 Release。
#
#   make release VERSION=0.2.0
#   SIGN_IDENTITY="Islet Dev" make release VERSION=0.2.0   # 用自簽憑證簽章，更新後權限不用重新允許
#
# 這一版的更新說明寫在 docs/release-notes/<版本>.md（可省略），會顯示在 Sparkle 的更新視窗與 GitHub Release 上。
# App 讀的是 releases/latest/download/appcast.xml，所以 appcast.xml 跟 DMG 一起上傳到每一版的 Release 就好。
# 簽 appcast 用的 EdDSA 私鑰在鑰匙圈裡（Sparkle 的 generate_keys 產生的）。
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

APP_NAME="Islet"
REPO="howardyu60211/Islet"
PLIST="Resources/Info.plist"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"
VERSION="${VERSION:-${1:-}}"
TAG="v$VERSION"
NOTES="docs/release-notes/$VERSION.md"
OUT="build/release"

die() { print -u2 "✗ $1"; exit 1 }

[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || die "用法：make release VERSION=x.y.z"
[[ -z "$(git status --porcelain)" ]] || die "還有沒 commit 的變更"
git rev-parse -q --verify "refs/tags/$TAG" > /dev/null && die "tag $TAG 已經存在"
if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
  print "⚠ 用 ad-hoc 簽章：使用者更新後要重新允許藍牙與完全磁碟取用權限。建議用 SIGN_IDENTITY 指定自簽憑證。"
fi

# 中途失敗或按 Ctrl-C 就把 Info.plist 改回去。從 HEAD 還原（連 staged 的一起），git add 之後 commit 失敗也還原得了
restore_plist() { git checkout -q HEAD -- "$PLIST" }
trap restore_plist ERR
trap 'restore_plist; exit 130' INT TERM

# Sparkle 比對的是 CFBundleVersion，每一版都要比上一版大
BUILD=$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$PLIST"
print "▸ 版本 $VERSION（$BUILD）"

./scripts/make-dmg.sh

print "▸ generate_appcast"
rm -rf "$OUT"
mkdir -p "$OUT"
cp "build/$APP_NAME-$VERSION.dmg" "$OUT/"
# 跟 DMG 同名的 .md 會被當成這一版的更新說明
[[ -f "$NOTES" ]] && cp "$NOTES" "$OUT/$APP_NAME-$VERSION.md"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --embed-release-notes \
  --link "https://github.com/$REPO" \
  -o "$OUT/appcast.xml" \
  "$OUT"

git add "$PLIST"
git commit -q -m "chore: release $VERSION"
git tag -a "$TAG" -m "$APP_NAME $VERSION"
trap - ERR INT TERM
print "✓ 已 commit 並建立 tag $TAG；要上傳的檔案在 $OUT/"

# 沒有 gh 或不想現在發佈時，印出手動步驟
manual() {
  print "\n手動發佈：\n  git push origin HEAD $TAG\n  到 https://github.com/$REPO/releases/new?tag=$TAG 上傳 $OUT/$APP_NAME-$VERSION.dmg 與 $OUT/appcast.xml"
}
if ! command -v gh > /dev/null; then
  print "找不到 gh（brew install gh 後執行 gh auth login 就能自動發佈）。"
  manual
  exit 0
fi
if ! read -q "?推上 GitHub 並建立 $TAG 的 Release？[y/N] "; then
  print
  manual
  exit 0
fi
print

git push origin HEAD "$TAG"
if [[ -f "$NOTES" ]]; then
  notes=(--notes-file "$NOTES")
else
  notes=(--generate-notes)
fi
gh release create "$TAG" "$OUT/$APP_NAME-$VERSION.dmg" "$OUT/appcast.xml" --repo "$REPO" --title "$APP_NAME $VERSION" "${notes[@]}"
print "✓ https://github.com/$REPO/releases/tag/$TAG"
