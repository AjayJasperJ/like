#!/usr/bin/env bash
set -euo pipefail
device_id="$1"
platform="$2"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
for state in provider riverpod bloc; do
  cd "$repo_root/examples/${state}_app"
  flutter create --platforms="$platform" --org dev.like.examples .
  rm -f test/widget_test.dart
  if [[ "$platform" == android ]]; then
    python3 ../../tool/configure_shop_platforms.py .
  fi
  flutter pub get
  python3 ../../tool/run_device_test.py "$device_id" "$platform" integration_test/flow_test.dart
done
cd "$repo_root/examples/provider_app"
python3 ../../tool/run_device_test.py "$device_id" "$platform" integration_test/live_api_test.dart
