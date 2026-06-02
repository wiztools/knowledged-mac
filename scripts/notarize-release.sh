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
SUBMISSION_ZIP=${SUBMISSION_ZIP:-"$BUILD_ROOT/KnowledgedMac-$STAMP-notary.zip"}
FINAL_ZIP=${FINAL_ZIP:-"$ARTIFACT_DIR/KnowledgedMac-$STAMP.zip"}

if [ ! -d "$APP_PATH" ]; then
  printf 'App not found: %s\n' "$APP_PATH" >&2
  printf 'Run scripts/build-release.sh first, or set APP_PATH.\n' >&2
  exit 2
fi

mkdir -p "$BUILD_ROOT" "$ARTIFACT_DIR"
rm -f "$SUBMISSION_ZIP" "$FINAL_ZIP"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$SUBMISSION_ZIP"

xcrun notarytool submit "$SUBMISSION_ZIP" \
  --keychain-profile "$KNOWLEDGED_MAC_NOTARY_PROFILE" \
  --wait

xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

printf 'Notarized app: %s\n' "$APP_PATH"
printf 'Distribution ZIP: %s\n' "$FINAL_ZIP"
