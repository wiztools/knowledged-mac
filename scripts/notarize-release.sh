#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

load_release_env
require_var KNOWLEDGED_MAC_NOTARY_PROFILE

BUILD_ROOT=${BUILD_ROOT:-"$ROOT_DIR/build/release"}
EXPORT_PATH=${EXPORT_PATH:-"$BUILD_ROOT/export"}
APP_PATH=${APP_PATH:-"$EXPORT_PATH/KnowledgedMac.app"}
ARTIFACT_DIR=${ARTIFACT_DIR:-"$ROOT_DIR/dist"}
STAMP=${RELEASE_STAMP:-$(timestamp)}
FINAL_ZIP=${FINAL_ZIP:-"$ARTIFACT_DIR/KnowledgedMac-$STAMP.zip"}
FINAL_DMG=${FINAL_DMG:-"$ARTIFACT_DIR/KnowledgedMac-$STAMP.dmg"}
DMG_SHA256=${DMG_SHA256:-"$FINAL_DMG.sha256"}
DMG_STAGING_DIR=${DMG_STAGING_DIR:-"$BUILD_ROOT/dmg-staging"}
DMG_VOLUME_NAME=${DMG_VOLUME_NAME:-"Knowledged Mac"}
SIGNING_CERTIFICATE=${KNOWLEDGED_MAC_SIGNING_CERTIFICATE:-Developer ID Application}

if [ ! -d "$APP_PATH" ]; then
  printf 'App not found: %s\n' "$APP_PATH" >&2
  printf 'Run scripts/build-release.sh first, or set APP_PATH.\n' >&2
  exit 2
fi

mkdir -p "$BUILD_ROOT" "$ARTIFACT_DIR"
rm -rf "$DMG_STAGING_DIR"
rm -f "$FINAL_ZIP" "$FINAL_DMG" "$DMG_SHA256"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

mkdir -p "$DMG_STAGING_DIR"
ditto "$APP_PATH" "$DMG_STAGING_DIR/$(basename "$APP_PATH")"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$FINAL_DMG"

codesign --force --sign "$SIGNING_CERTIFICATE" "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG" > "$DMG_SHA256"

xcrun notarytool submit "$FINAL_DMG" \
  --keychain-profile "$KNOWLEDGED_MAC_NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG" > "$DMG_SHA256"

xcrun stapler validate "$FINAL_DMG"
codesign --verify --verbose=2 "$FINAL_DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$FINAL_DMG"

printf 'Signed app: %s\n' "$APP_PATH"
printf 'Distribution ZIP: %s\n' "$FINAL_ZIP"
printf 'Notarized DMG: %s\n' "$FINAL_DMG"
printf 'Post-staple SHA-256: %s\n' "$DMG_SHA256"
