#!/bin/sh
# Xcode Cloud: install Flutter and iOS deps after git clone, before xcodebuild.
#
# Workflow (App Store Connect / Xcode, not in git):
#   Workspace  ios/Runner.xcworkspace
#   Scheme     Runner
#   Archive    Release
# Disable the old FabricLab.xcodeproj workflow or it will keep shipping the Swift app.
#
# Optional: set API_BASE_URL on the workflow to override the default server.

set -e

cd "${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)}"

FLUTTER_VERSION=3.47.5
FLUTTER_DIR="${HOME}/flutter"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"
export FLUTTER_ROOT="${FLUTTER_DIR}"

flutter precache --ios
flutter pub get

if [ -n "${API_BASE_URL:-}" ]; then
  flutter build ios --config-only --release --dart-define="API_BASE_URL=${API_BASE_URL}"
else
  flutter build ios --config-only --release
fi

if ! command -v pod >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
fi

cd ios
pod install
