#!/bin/zsh
# Rebuilds Roost Menu and launches it. Add --demo to use fake devices.
# Needs Xcode and xcodegen (brew install xcodegen). Signing and bundle ID come from Config/ (see SETUP.md).
cd "$(dirname "$0")"
if [[ ! -f Config/Local.xcconfig ]]; then
  echo "Note: no Config/Local.xcconfig, so this builds with the default bundle ID and ad-hoc signing."
  echo "      Copy Config/Local.xcconfig.example to Config/Local.xcconfig to use your own."
fi
xcodegen generate >/dev/null && \
xcodebuild -project RoostMenu.xcodeproj -scheme RoostMenu -configuration Debug -derivedDataPath build build -quiet && \
pkill -x RoostMenu; open -n build/Build/Products/Debug/RoostMenu.app --args "$@"
