#!/bin/sh
set -eu

mode="${1:-check}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

write_output() {
  key="$1"
  value="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  fi
}

clean_worktree() {
  if [ -n "$(git status --porcelain)" ]; then
    echo "working tree must be clean before running release automation" >&2
    git status --short >&2
    exit 1
  fi
}

latest_version() {
  version="$(git tag --list 'v[0-9]*' | sed 's/^v//' | sort -V | tail -n 1)"
  if [ -n "$version" ]; then
    printf '%s\n' "$version"
  else
    printf '0.0.0\n'
  fi
}

fragment_files() {
  find .changes -maxdepth 1 -type f ! -name README.md | sort
}

fragment_bump() {
  awk '
    NF {
      line = tolower($0)
      sub(/:.*/, "", line)
      print line
      exit
    }
  ' "$1"
}

release_notes() {
  awk '
    BEGIN { seen = 0 }
    seen == 0 && NF { seen = 1; next }
    seen == 1 { print }
  ' "$1"
}

bump_version() {
  version="$1"
  bump="$2"

  major="$(printf '%s' "$version" | cut -d. -f1)"
  minor="$(printf '%s' "$version" | cut -d. -f2)"
  patch="$(printf '%s' "$version" | cut -d. -f3)"

  case "$bump" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    *)
      echo "invalid bump level: $bump" >&2
      exit 1
      ;;
  esac

  printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

highest_bump() {
  highest="patch"
  for file in $(fragment_files); do
    bump="$(fragment_bump "$file")"
    case "$bump" in
      major)
        highest="major"
        break
        ;;
      minor)
        if [ "$highest" != "major" ]; then
          highest="minor"
        fi
        ;;
      patch)
        ;;
      *)
        echo "invalid release fragment header in $file: expected patch|minor|major" >&2
        exit 1
        ;;
    esac
  done
  printf '%s\n' "$highest"
}

run_checks() {
  dune build nats-client.opam nats-client-async.opam
  git diff --exit-code -- nats-client.opam nats-client-async.opam
  dune runtest
  dune-release lint
}

prepare_pr() {
  clean_worktree

  if [ ! -d .changes ]; then
    write_output "has_changes" "false"
    echo ".changes/ is missing" >&2
    exit 1
  fi

  files="$(fragment_files || true)"
  if [ -z "$files" ]; then
    write_output "has_changes" "false"
    echo "no release fragments found"
    exit 0
  fi

  run_checks

  bump="$(highest_bump)"
  current="$(latest_version)"
  next="$(bump_version "$current" "$bump")"
  today="$(date -u +%Y-%m-%d)"
  tmp="$(mktemp)"

  {
    printf '# Changelog\n\n'
    printf '## %s - %s\n\n' "$next" "$today"
    for file in $files; do
      release_notes "$file"
      printf '\n'
    done
    if [ -f CHANGES.md ]; then
      tail -n +2 CHANGES.md
    fi
  } > "$tmp"

  mv "$tmp" CHANGES.md
  rm -f $files

  write_output "has_changes" "true"
  write_output "next_version" "$next"
  echo "prepared release PR content for v$next"
}

publish_release() {
  clean_worktree
  tag="$(git describe --tags --exact-match 2>/dev/null)" || {
    echo "publish mode requires an exact v* tag on HEAD" >&2
    exit 1
  }
  version="${tag#v}"
  dist_file="_build/nats-client-${version}.tbz"

  run_checks
  dune-release distrib

  if gh release view "$tag" >/dev/null 2>&1; then
    echo "github release $tag already exists; skipping dune-release publish"
  else
    yes | dune-release publish
  fi

  if [ -z "${OPAM_PUBLISH_GH_TOKEN:-}" ]; then
    echo "OPAM_PUBLISH_GH_TOKEN is required for dune-release opam submit in CI" >&2
    exit 1
  fi

  # Preserve the leading `v` in Git tags so the generated release archive URL
  # matches GitHub's releases/download/vX.Y.Z/... path, while still pointing at
  # the archive filename created by `dune-release distrib`.
  dune-release opam pkg --keep-v --tag "$tag" --pkg-version "$version" --dist-file "$dist_file"
  yes | dune-release opam submit --keep-v --tag "$tag" --pkg-version "$version" --dist-file "$dist_file" --user Hebilicious --no-auto-open
}

require git
require dune
require opam
require dune-release

case "$mode" in
  check)
    clean_worktree
    run_checks
    echo "release preflight OK"
    ;;
  prepare-pr)
    prepare_pr
    ;;
  publish)
    publish_release
    ;;
  *)
    echo "usage: $0 [check|prepare-pr|publish]" >&2
    exit 2
    ;;
esac
