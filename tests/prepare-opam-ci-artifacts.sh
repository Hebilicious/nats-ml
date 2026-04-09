#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
OUT_DIR=${1:-}

if [[ -z "$OUT_DIR" ]]; then
  echo "usage: $0 <output-dir>" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

version_from_git() {
  local latest

  latest=$(git -C "$REPO_ROOT" tag --list 'v[0-9]*' | sed 's/^v//' | sort -V | tail -n 1)
  if [[ -n "$latest" ]]; then
    printf '%s\n' "$latest"
  else
    printf '0.0.0\n'
  fi
}

sha256_file() {
  local file=$1

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

append_url_block() {
  local source_opam=$1
  local target_opam=$2
  local archive_url=$3
  local archive_sha=$4

  cp "$source_opam" "$target_opam"
  cat >>"$target_opam" <<EOF

url {
  src: "$archive_url"
  checksum: "sha256=$archive_sha"
}
EOF
}

PACKAGE_VERSION=${NATS_ML_OPAM_CI_PACKAGE_VERSION:-$(version_from_git)}
ARCHIVE_BASENAME="nats-client-$PACKAGE_VERSION"
ARCHIVE_DIR="$OUT_DIR/dist"
ARCHIVE_PATH="$ARCHIVE_DIR/$ARCHIVE_BASENAME.tar.gz"
LOCAL_REPO_ROOT="$OUT_DIR/repo"

mkdir -p "$ARCHIVE_DIR"
for package in nats-client nats-client-async; do
  mkdir -p "$LOCAL_REPO_ROOT/packages/$package/$package.$PACKAGE_VERSION"
done

git -C "$REPO_ROOT" archive \
  --format=tar.gz \
  --prefix="$ARCHIVE_BASENAME/" \
  --output="$ARCHIVE_PATH" \
  HEAD

ARCHIVE_SHA=$(sha256_file "$ARCHIVE_PATH")
ARCHIVE_DIR_URL=${NATS_ML_OPAM_CI_ARCHIVE_DIR_URL:-file://$ARCHIVE_DIR}
ARCHIVE_URL="$ARCHIVE_DIR_URL/$ARCHIVE_BASENAME.tar.gz"

for package in nats-client nats-client-async; do
  append_url_block \
    "$REPO_ROOT/$package.opam" \
    "$LOCAL_REPO_ROOT/packages/$package/$package.$PACKAGE_VERSION/opam" \
    "$ARCHIVE_URL" \
    "$ARCHIVE_SHA"
done

cat >"$LOCAL_REPO_ROOT/repo" <<EOF
opam-version: "2.0"
upstream: "file://$REPO_ROOT"
EOF

printf '%s\n' "$PACKAGE_VERSION" >"$OUT_DIR/version"
chmod -R a+rX "$OUT_DIR"
