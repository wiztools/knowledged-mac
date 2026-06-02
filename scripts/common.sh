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
