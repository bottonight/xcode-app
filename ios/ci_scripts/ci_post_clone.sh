#!/bin/sh
# Xcode Cloud: install Flutter and iOS deps after git clone, before xcodebuild.
# Workflow must use ios/Runner.xcworkspace / Scheme Runner (Release).
# Optional workflow env: API_BASE_URL

set -e

echo "=== repo root ==="
cd "${CI_PRIMARY_REPOSITORY_PATH:-$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)}"
pwd

export CI=true
export PUB_ENVIRONMENT=flutter_bot

FLUTTER_VERSION=3.47.5
FLUTTER_DIR="${HOME}/flutter"
export PATH="${FLUTTER_DIR}/bin:${PATH}"
export FLUTTER_ROOT="${FLUTTER_DIR}"

install_flutter_zip() {
  arch="$(uname -m)"
  if [ "${arch}" = "arm64" ]; then
    zip_name="flutter_macos_arm64_${FLUTTER_VERSION}-stable.zip"
  else
    zip_name="flutter_macos_${FLUTTER_VERSION}-stable.zip"
  fi
  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/${zip_name}"
  echo "=== download ${url} ==="
  curl -fL --retry 3 --retry-delay 5 -o "/tmp/${zip_name}" "${url}"
  echo "=== unzip Flutter SDK ==="
  rm -rf "${FLUTTER_DIR}"
  unzip -q "/tmp/${zip_name}" -d "${HOME}"
  rm -f "/tmp/${zip_name}"
}

echo "=== install Flutter ${FLUTTER_VERSION} ==="
if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  if ! git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_DIR}"; then
    echo "git clone failed, falling back to release zip"
    install_flutter_zip
  fi
fi

echo "=== flutter config ==="
flutter config --no-analytics
flutter --version
flutter precache --ios

echo "=== flutter pub get ==="
flutter pub get

echo "=== CocoaPods ==="
if ! command -v pod >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
fi

echo "=== pod install ==="
cd ios
pod install
cd ..

echo "=== flutter build ios --config-only ==="
if [ -n "${API_BASE_URL:-}" ]; then
  flutter build ios --config-only --release --no-codesign --dart-define="API_BASE_URL=${API_BASE_URL}"
else
  flutter build ios --config-only --release --no-codesign
fi

echo "=== ci_post_clone done ==="
exit 0
