#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

load_release_env
require_var KNOWLEDGED_MAC_TEAM_ID

PROJECT_PATH=${PROJECT_PATH:-"$ROOT_DIR/KnowledgedMac.xcodeproj"}
SCHEME=${SCHEME:-KnowledgedMac}
CONFIGURATION=${CONFIGURATION:-Release}
BUILD_ROOT=${BUILD_ROOT:-"$ROOT_DIR/build/release"}
ARCHIVE_PATH=${ARCHIVE_PATH:-"$BUILD_ROOT/KnowledgedMac.xcarchive"}
EXPORT_PATH=${EXPORT_PATH:-"$BUILD_ROOT/export"}
EXPORT_OPTIONS_PATH=${EXPORT_OPTIONS_PATH:-"$BUILD_ROOT/ExportOptions.plist"}
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-"$BUILD_ROOT/DerivedData"}

BUNDLE_ID=${KNOWLEDGED_MAC_BUNDLE_ID:-com.wiztools.KnowledgedMac}
MARKETING_VERSION=${KNOWLEDGED_MAC_VERSION:-}
CURRENT_PROJECT_VERSION=${KNOWLEDGED_MAC_BUILD:-}
SIGNING_CERTIFICATE=${KNOWLEDGED_MAC_SIGNING_CERTIFICATE:-Developer ID Application}

mkdir -p "$BUILD_ROOT"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

cat > "$EXPORT_OPTIONS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>teamID</key>
	<string>$KNOWLEDGED_MAC_TEAM_ID</string>
	<key>signingCertificate</key>
	<string>$SIGNING_CERTIFICATE</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
EOF

set -- \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  "DEVELOPMENT_TEAM=$KNOWLEDGED_MAC_TEAM_ID" \
  "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
  "CODE_SIGN_STYLE=Manual" \
  "CODE_SIGN_IDENTITY=$SIGNING_CERTIFICATE" \
  "ENABLE_HARDENED_RUNTIME=YES"

if [ -n "$MARKETING_VERSION" ]; then
  set -- "$@" "MARKETING_VERSION=$MARKETING_VERSION"
fi

if [ -n "$CURRENT_PROJECT_VERSION" ]; then
  set -- "$@" "CURRENT_PROJECT_VERSION=$CURRENT_PROJECT_VERSION"
fi

xcodebuild "$@" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH"

APP_PATH="$EXPORT_PATH/KnowledgedMac.app"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

printf 'Developer ID signed app: %s\n' "$APP_PATH"
printf 'Next: scripts/notarize-release.sh\n'
