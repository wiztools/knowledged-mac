#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

APP_NAME=KnowledgedMac
INFO_PLIST="$ROOT_DIR/KnowledgedMac/Info.plist"
BUILD_COUNTER=1

usage() {
  printf 'Usage: %s [--build-counter <number>]\n' "$0" >&2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-counter)
      if [ "$#" -lt 2 ]; then
        usage
        exit 2
      fi
      BUILD_COUNTER=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

case "$BUILD_COUNTER" in
  ''|*[!0-9]*)
    printf 'Build counter must be a number: %s\n' "$BUILD_COUNTER" >&2
    exit 2
    ;;
esac

if [ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]; then
  printf 'Refusing to release: git worktree is not clean.\n' >&2
  git -C "$ROOT_DIR" status --short >&2
  exit 2
fi

HEAD_TAGS=$(git -C "$ROOT_DIR" tag --points-at HEAD)
RELEASE_TAGS=$(printf '%s\n' "$HEAD_TAGS" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)
RELEASE_TAG_COUNT=$(printf '%s\n' "$RELEASE_TAGS" | sed '/^$/d' | wc -l | tr -d ' ')

if [ "$RELEASE_TAG_COUNT" -ne 1 ]; then
  printf 'Refusing to release: HEAD must have exactly one semver tag like v1.2.3.\n' >&2
  printf 'Tags on HEAD:\n' >&2
  if [ -n "$HEAD_TAGS" ]; then
    printf '%s\n' "$HEAD_TAGS" >&2
  else
    printf '(none)\n' >&2
  fi
  exit 2
fi

RELEASE_TAG=$RELEASE_TAGS
APP_VERSION=${RELEASE_TAG#v}
BUILD_VERSION=$(date "+%Y%m%d").$BUILD_COUNTER
GIT_COMMIT=$(git -C "$ROOT_DIR" rev-parse HEAD)

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$INFO_PLIST"
if ! /usr/libexec/PlistBuddy -c "Set :${APP_NAME}GitCommit $GIT_COMMIT" "$INFO_PLIST" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c "Add :${APP_NAME}GitCommit string $GIT_COMMIT" "$INFO_PLIST"
fi

export KNOWLEDGED_MAC_VERSION=$APP_VERSION
export KNOWLEDGED_MAC_BUILD=$BUILD_VERSION
export KNOWLEDGED_MAC_RELEASE_TAG=$RELEASE_TAG

printf 'Release metadata:\n'
printf '  APP_VERSION=%s\n' "$APP_VERSION"
printf '  BUILD_VERSION=%s\n' "$BUILD_VERSION"
printf '  RELEASE_TAG=%s\n' "$RELEASE_TAG"
printf '  GIT_COMMIT=%s\n' "$GIT_COMMIT"

"$SCRIPT_DIR/build-release.sh"
"$SCRIPT_DIR/notarize-release.sh"
