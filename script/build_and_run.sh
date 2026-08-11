#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="SpendScope"
BUNDLE_ID="com.ychp.SpendScope"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/SpendScope.xcodeproj"
SCHEME="SpendScope"
# Never share incremental build state between separate checkouts or worktrees.
WORKSPACE_KEY="$(printf '%s' "$ROOT_DIR" | shasum -a 256 | awk '{print substr($1, 1, 12)}')"
DERIVED_DATA="${SPENDSCOPE_DERIVED_DATA:-/private/tmp/SpendScope-DerivedData-$WORKSPACE_KEY}"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
BUILD_INPUT_FINGERPRINT_FILE="$DERIVED_DATA/.spendscope-build-inputs.sha256"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Content hashing makes cache invalidation independent of file modification times.
build_input_fingerprint() {
  (
    cd "$ROOT_DIR"
    {
      find Sources Config -type f -print
      find SpendScope.xcodeproj -type f ! -path "*/xcuserdata/*" -print
      printf '%s\n' "script/build_and_run.sh"
    } | LC_ALL=C sort | while IFS= read -r path; do
      shasum -a 256 "$path"
    done
  ) | shasum -a 256 | awk '{print $1}'
}

xcodebuild_for_app() {
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    "$@" \
    -quiet
}

stop_app() {
  local attempt

  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  for attempt in {1..50}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done

  echo "error: existing $APP_NAME process did not exit" >&2
  exit 1
}

CURRENT_BUILD_INPUT_FINGERPRINT="$(build_input_fingerprint)"
CACHED_BUILD_INPUT_FINGERPRINT=""
if [[ -f "$BUILD_INPUT_FINGERPRINT_FILE" ]]; then
  CACHED_BUILD_INPUT_FINGERPRINT="$(<"$BUILD_INPUT_FINGERPRINT_FILE")"
fi

stop_app

echo "Building $APP_NAME from $ROOT_DIR (inputs ${CURRENT_BUILD_INPUT_FINGERPRINT:0:12})..."
if [[ -d "$DERIVED_DATA/Build" && "$CACHED_BUILD_INPUT_FINGERPRINT" != "$CURRENT_BUILD_INPUT_FINGERPRINT" ]]; then
  echo "Build inputs changed; cleaning this workspace's DerivedData..."
  xcodebuild_for_app clean
fi
xcodebuild_for_app build

if [[ ! -x "$APP_BINARY" ]]; then
  echo "error: app binary not found at $APP_BINARY" >&2
  exit 1
fi

mkdir -p "$DERIVED_DATA"
printf '%s\n' "$CURRENT_BUILD_INPUT_FINGERPRINT" >"$BUILD_INPUT_FINGERPRINT_FILE"
APP_BINARY_FINGERPRINT="$(shasum -a 256 "$APP_BINARY" | awk '{print substr($1, 1, 12)}')"

open_app() {
  # Another Run action may have completed while this invocation was building.
  # Stop once more immediately before launch, then let LaunchServices reuse the
  # bundle identity instead of explicitly forcing a parallel app instance.
  stop_app
  /usr/bin/open "$APP_BUNDLE"
}

verify_app() {
  local attempt

  for attempt in {1..50}; do
    if pgrep -f -x "$APP_BINARY" >/dev/null; then
      echo "$APP_NAME is running from $APP_BUNDLE (binary $APP_BINARY_FINGERPRINT)."
      return
    fi
    sleep 0.1
  done

  echo "error: freshly built app is not running at $APP_BINARY" >&2
  exit 1
}

open_and_verify_app() {
  open_app
  verify_app
}

case "$MODE" in
  run)
    open_and_verify_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_and_verify_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_and_verify_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_and_verify_app
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
