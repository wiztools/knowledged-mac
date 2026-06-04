#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

load_release_env() {
  if [ -f "$SCRIPT_DIR/release.env" ]; then
    # shellcheck disable=SC1091
    . "$SCRIPT_DIR/release.env"
  fi
}

require_var() {
  name=$1
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    printf 'Missing required environment variable: %s\n' "$name" >&2
    printf 'Copy scripts/release.env.example to scripts/release.env and fill in your local values.\n' >&2
    exit 2
  fi
}

timestamp() {
  date -u "+%Y%m%dT%H%M%SZ"
}

semver_tag_at_head() {
  tags=$(git -C "$ROOT_DIR" tag --points-at HEAD)
  release_tags=$(printf '%s\n' "$tags" | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)
  release_tag_count=$(printf '%s\n' "$release_tags" | sed '/^$/d' | wc -l | tr -d ' ')

  if [ "$release_tag_count" -eq 1 ]; then
    printf '%s\n' "$release_tags"
  fi

  return 0
}

release_artifact_version() {
  if [ -n "${KNOWLEDGED_MAC_ARTIFACT_VERSION:-}" ]; then
    printf '%s\n' "$KNOWLEDGED_MAC_ARTIFACT_VERSION"
    return
  fi

  if [ -n "${KNOWLEDGED_MAC_RELEASE_TAG:-}" ]; then
    printf '%s\n' "$KNOWLEDGED_MAC_RELEASE_TAG"
    return
  fi

  semver_tag=$(semver_tag_at_head)
  if [ -n "$semver_tag" ]; then
    printf '%s\n' "$semver_tag"
    return
  fi

  if [ -n "${KNOWLEDGED_MAC_VERSION:-}" ]; then
    printf 'v%s\n' "$KNOWLEDGED_MAC_VERSION"
    return
  fi

  timestamp
}
