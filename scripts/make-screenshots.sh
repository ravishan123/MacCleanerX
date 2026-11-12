#!/bin/zsh
# Captures README/website screenshots of every screen into docs/images/screenshots/.
# Uses the Debug build's -screenshotScreen/-screenshotScan launch arguments (scans are read-only).
# The terminal needs Screen Recording permission. Review every image before committing:
# scan results show real file and app names from this Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="build/DerivedData/Build/Products/Debug/Mac Cleaner.app"
OUT="docs/images/screenshots"
mkdir -p "$OUT"
TMP=$(mktemp -d)
cat > "$TMP/winid.swift" <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "Mac Cleaner"
    && (w["kCGWindowName"] as? String) == "Mac Cleaner" { print(w["kCGWindowNumber"]!); break }
SWIFT
swiftc -O "$TMP/winid.swift" -o "$TMP/winid" 2>/dev/null

# name  screen  scan  seconds-to-wait
shots=(
  "smart-care      smartCare   NO  3"
  "cleanup         cleanup     YES 40"
  "storage         storage     YES 240"
  "large-files     largeFiles  NO  3"
  "uninstaller     uninstaller NO  15"
  "settings        settings    NO  3"
)
for line in "${shots[@]}"; do
  read -r name screen scan wait <<< "$line"
  pkill -x "Mac Cleaner" 2>/dev/null || true; sleep 1
  open -n "$APP" --args -screenshotScreen "$screen" -screenshotScan "$scan" -AppleInterfaceStyle Dark
  sleep "$wait"
  id=$("$TMP/winid")
  screencapture -o -x -l "$id" "$OUT/$name.png"
  sips -Z 1600 "$OUT/$name.png" >/dev/null
  echo "captured $name"
done
pkill -x "Mac Cleaner" 2>/dev/null || true
rm -rf "$TMP"
