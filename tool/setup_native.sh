#!/usr/bin/env bash
# Creates the iOS/Android projects for both apps, applies store settings,
# fetches packages and generates icons and splash screens.
#
#   ./tool/setup_native.sh            # both apps
#   ./tool/setup_native.sh driver     # one app
#
# Needs Flutter (3.27+), Python 3, and on macOS Xcode + CocoaPods.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPS=("${@:-passenger driver}")
# shellcheck disable=SC2206
APPS=(${APPS[@]})

(cd "$ROOT/packages/core" && flutter pub get)

for app in "${APPS[@]}"; do
  echo "=== $app ==="
  cd "$ROOT/apps/$app"
  # Existing files (lib/, pubspec.yaml) are kept; only missing platform folders are generated.
  flutter create --org com.nomo --project-name "$app" --platforms android,ios .
  rm -f test/widget_test.dart # template test for the counter app
  flutter pub get
  python3 "$ROOT/tool/patch_native.py" "$app"
  dart run flutter_launcher_icons
  dart run flutter_native_splash:create
  if [[ "$(uname)" == "Darwin" ]]; then
    (cd ios && pod install --repo-update)
  fi
done

echo
echo "Done. Next:"
echo "  cd apps/passenger && flutter run --dart-define=API_URL=http://<your-computer-ip>:8080"
