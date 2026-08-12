#!/usr/bin/env bash
set -euo pipefail

: "${PAGES_SITE_DIR:?set PAGES_SITE_DIR to the verified site directory}"
: "${PAGES_ARCHIVE_FILE:?set PAGES_ARCHIVE_FILE to a new absolute artifact.tar path}"

for command in basename dirname find grep realpath tar; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: required command is unavailable: $command" >&2
    exit 1
  fi
done
if [[ "$PAGES_SITE_DIR" != /* ]] ||
  [[ "$PAGES_ARCHIVE_FILE" != /* ]] ||
  [[ "$PAGES_ARCHIVE_FILE" == "/" ]] ||
  [[ ! -d "$PAGES_SITE_DIR" ]] ||
  [[ -L "$PAGES_SITE_DIR" ]] ||
  [[ -e "$PAGES_ARCHIVE_FILE" ]] ||
  [[ -L "$PAGES_ARCHIVE_FILE" ]]; then
  echo "ERROR: Pages archive inputs must be canonical absolute, non-symlink paths and output must be new." >&2
  exit 2
fi

site_dir="$(realpath -e -- "$PAGES_SITE_DIR")"
archive_parent="$(realpath -e -- "$(dirname "$PAGES_ARCHIVE_FILE")")"
archive_file="$archive_parent/$(basename "$PAGES_ARCHIVE_FILE")"
if [[ "$PAGES_SITE_DIR" != "$site_dir" ]] ||
  [[ "$PAGES_ARCHIVE_FILE" != "$archive_file" ]]; then
  echo "ERROR: Pages archive paths must already be canonical." >&2
  exit 2
fi
case "$archive_file" in
  "$site_dir"/*)
    echo "ERROR: Pages archive must be outside the site directory." >&2
    exit 2
    ;;
esac
if find "$site_dir" -type l -print -quit | grep -q .; then
  echo "ERROR: Pages site contains a symlink." >&2
  exit 1
fi

tar \
  --dereference \
  --hard-dereference \
  --directory "$site_dir" \
  --create \
  --file "$archive_file" \
  --exclude=.git \
  --exclude=.github \
  .

echo "Created exact GitHub Pages tar artifact at $archive_file."
