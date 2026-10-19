#!/bin/zsh
# 重新產生 README 用的截圖到 docs/images：Debug 建置後用快照模式畫出各種狀態（不畫瀏海紅框），再裁掉多餘的桌布。
#
#   ./scripts/screenshots.sh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

OUT="docs/images"
RAW="$(mktemp -d)"
trap 'rm -rf "$RAW"' EXIT

echo "▸ swift build (debug)"
swift build -c debug --product DynamicIsland
BIN="$(swift build -c debug --show-bin-path)/DynamicIsland"

echo "▸ 產生快照"
"$BIN" --snapshots "$RAW" --no-guides > /dev/null
"$BIN" --settings-snapshots "$RAW" > /dev/null

mkdir -p "$OUT"
rm -f "$OUT"/*.png(N)

# crop <快照名稱> <輸出名稱> <高> <寬> <上> <左>（2x 像素；快照原圖是 1440×520，瀏海在正中間）
crop() {
  sips -c "$3" "$4" --cropOffset "$5" "$6" "$RAW/$1.png" --out "$OUT/$2.png" > /dev/null
  echo "✓ $OUT/$2.png"
}
compact() { crop "$1" "$2" 120 900 0 270; }
banner() { crop "$1" "$2" 220 900 0 270; }
expanded() { crop "$1" "$2" 400 1320 0 60; }

expanded 06-expanded-media              expanded-media
expanded 07-expanded-shelf              expanded-shelf
expanded 08-expanded-timer              expanded-timer
expanded 14c-expanded-clipboard-wheel   expanded-clipboard

compact 09-compact-now-playing          compact-now-playing
compact 16-compact-pair-music-timer     compact-music-timer
compact 02-compact-charging             compact-charging
compact 11-compact-volume               compact-volume
compact 12-compact-focus-on             compact-focus
compact 13-compact-microphone           compact-microphone
compact 15-compact-clipboard-text       compact-clipboard

banner 03-banner-bluetooth              banner-airpods
banner 05-banner-timer                  banner-timer
banner 04-banner-low-battery            banner-low-battery

cp "$RAW/settings-general.png" "$OUT/settings-general.png"
echo "✓ $OUT/settings-general.png"
