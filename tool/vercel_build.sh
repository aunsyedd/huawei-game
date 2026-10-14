#!/usr/bin/env bash
# Builds the Flutter web app on Vercel (its build image has no Flutter).
# Vercel runs this for every Git push; output goes to build/web (see vercel.json).
set -euo pipefail

FLUTTER_VERSION=3.47.5

if [ ! -x flutter-sdk/bin/flutter ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git flutter-sdk
fi
export PATH="$PWD/flutter-sdk/bin:$PATH"

flutter config --no-analytics --enable-web > /dev/null
flutter --version
flutter pub get
flutter build web --release
