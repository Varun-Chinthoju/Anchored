#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Anchored"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_PATH="/Applications/$APP_NAME.app"

BUILD_CONFIGURATION="Release"
LAUNCH_WITH_Lldb="no"

case "$MODE" in
  run)
    BUILD_CONFIGURATION="Release"
    ;;
  debug)
    BUILD_CONFIGURATION="Debug"
    ;;
  --debug|lldb)
    BUILD_CONFIGURATION="Debug"
    LAUNCH_WITH_Lldb="yes"
    ;;
  --logs|logs|--telemetry|telemetry|--verify|verify)
    BUILD_CONFIGURATION="Release"
    ;;
  -h|--help|help)
    cat <<'EOF'
usage: ./script/build_and_run.sh [run|debug|--debug|--logs|--telemetry|--verify]

  run       Build Release, install to /Applications, and launch.
  debug     Build Debug, install to /Applications, and launch.
  --debug   Build Debug, install to /Applications, and launch under lldb.
  --logs    Build Release, install to /Applications, launch, then stream logs.
  --telemetry  Same as --logs for now.
  --verify  Build Release, install to /Applications, launch, and confirm the process exists.
EOF
    exit 0
    ;;
  *)
    echo "usage: $0 [run|debug|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

BUILD_CONFIGURATION_LOWER="$(printf '%s' "$BUILD_CONFIGURATION" | tr '[:upper:]' '[:lower:]')"
DERIVED_DATA_DIR="$(mktemp -d "${TMPDIR:-/private/tmp}/anchored-${BUILD_CONFIGURATION_LOWER}-derived-data.XXXXXX")"
BUILT_APP="$DERIVED_DATA_DIR/Build/Products/$BUILD_CONFIGURATION/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT_ROOT/Anchored.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$BUILD_CONFIGURATION" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

test -d "$BUILT_APP"
/bin/rm -rf "$INSTALL_PATH"
/usr/bin/ditto "$BUILT_APP" "$INSTALL_PATH"

# The default scheme builds the unit-test host bundle. Trim those test-only
# artifacts back out of the installed app so the shipping copy stays lean.
for path in \
  "$INSTALL_PATH/Contents/PlugIns/AnchoredTests.xctest" \
  "$INSTALL_PATH/Contents/Frameworks/XCUnit.framework" \
  "$INSTALL_PATH/Contents/Frameworks/XCTAutomationSupport.framework" \
  "$INSTALL_PATH/Contents/Frameworks/XCUIAutomation.framework" \
  "$INSTALL_PATH/Contents/Frameworks/XCTestSupport.framework" \
  "$INSTALL_PATH/Contents/Frameworks/XCTest.framework" \
  "$INSTALL_PATH/Contents/Frameworks/XCTestCore.framework" \
  "$INSTALL_PATH/Contents/Frameworks/Testing.framework" \
  "$INSTALL_PATH/Contents/Frameworks/libXCTestBundleInject.dylib" \
  "$INSTALL_PATH/Contents/Frameworks/libXCTestSwiftSupport.dylib"; do
  /bin/rm -rf "$path"
done
find "$INSTALL_PATH/Contents/Frameworks" -name "*PackageProduct.framework" -exec /bin/rm -rf {} + 2>/dev/null || true

open_app() {
  /usr/bin/open -n "$INSTALL_PATH"
}

if [[ "$LAUNCH_WITH_Lldb" == "yes" ]]; then
  exec lldb -- "$INSTALL_PATH/Contents/MacOS/$APP_NAME"
fi

case "$MODE" in
  run|debug)
    open_app
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
esac
