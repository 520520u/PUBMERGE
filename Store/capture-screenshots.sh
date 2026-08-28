#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Store/Screenshots"
IPHONE="FD87E757-27EE-4C8C-A9A3-E494B9BCDB74"
IPAD="59560898-17CC-40A7-B2FC-02F72608BB36"
BUNDLE="app.pubmerge.PubMerge"
SCENES=(importCopies compare conflicts export settings)

mkdir -p "$DEST/iPhone-6.9" "$DEST/iPad-13" "$DEST/Mac"

echo "Building iOS Simulator…"
xcodebuild -project "$ROOT/PubMerge.xcodeproj" -scheme PubMerge \
  -destination "platform=iOS Simulator,id=$IPHONE" -configuration Debug build \
  >/tmp/pubmerge-ios-build.log
APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/PubMerge-"*/Build/Products/Debug-iphonesimulator/PubMerge.app -maxdepth 0 | head -1)

capture_sim() {
  local udid="$1" folder="$2" width="$3" height="$4"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b
  xcrun simctl install "$udid" "$APP"
  xcrun simctl status_bar "$udid" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --batteryState charged --batteryLevel 100 || true
  local i=1
  for scene in "${SCENES[@]}"; do
    xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$udid" "$BUNDLE" -demoStoreScreenshots -demoStep "$scene" -AppleLanguages "(en)" -AppleLocale en_US
    sleep 5
    local tmp="/tmp/pubmerge-$folder-$scene.png"
    xcrun simctl io "$udid" screenshot "$tmp"
    python3 - "$tmp" "$DEST/$folder/$(printf '%02d' $i)-$scene.jpg" "$width" "$height" <<'PY'
import sys
from PIL import Image
src, dst, w, h = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
im = Image.open(src).convert("RGB")
if im.size != (w, h):
    im = im.resize((w, h), Image.Resampling.LANCZOS)
im.save(dst, "JPEG", quality=92, optimize=True)
print(dst, im.size)
PY
    i=$((i + 1))
  done
}

echo "Capturing iPhone…"
capture_sim "$IPHONE" "iPhone-6.9" 1320 2868
echo "Capturing iPad…"
capture_sim "$IPAD" "iPad-13" 2064 2752
echo "Done iOS. Mac window capture is separate."
