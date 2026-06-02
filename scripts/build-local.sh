#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

PROJECT_PATH=${PROJECT_PATH:-"$ROOT_DIR/KnowledgedMac.xcodeproj"}
SCHEME=${SCHEME:-KnowledgedMac}
CONFIGURATION=${CONFIGURATION:-Release}
DERIVED_DATA_PATH=${DERIVED_DATA_PATH:-"$ROOT_DIR/build/DerivedData"}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT_DIR/build/local"}

APP_SOURCE="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/KnowledgedMac.app"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/KnowledgedMac.app"
cp -R "$APP_SOURCE" "$OUTPUT_DIR/"

printf 'Built %s\n' "$OUTPUT_DIR/KnowledgedMac.app"
