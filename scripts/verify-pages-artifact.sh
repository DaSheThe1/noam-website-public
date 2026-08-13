#!/usr/bin/env bash
set -euo pipefail

: "${PAGES_SITE_DIR:?set PAGES_SITE_DIR to the prepared site directory}"
: "${PAGES_HANDOFF_FILE:?set PAGES_HANDOFF_FILE to foundation/pages-publication.json}"
: "${EXPECTED_SOURCE_COMMIT:?set the approved private source commit}"
: "${EXPECTED_PROVENANCE_SHA256:?set the approved static provenance digest}"

if [[ ! "$EXPECTED_SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
  [[ ! "$EXPECTED_PROVENANCE_SHA256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ERROR: expected source and provenance values must be full lowercase digests." >&2
  exit 2
fi
for command in cut find grep jq realpath sha256sum sort tr; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: required command is unavailable: $command" >&2
    exit 1
  fi
done
if [[ ! -d "$PAGES_SITE_DIR" ]] ||
  [[ ! -f "$PAGES_HANDOFF_FILE" ]] ||
  [[ -L "$PAGES_SITE_DIR" ]] ||
  [[ -L "$PAGES_HANDOFF_FILE" ]]; then
  echo "ERROR: Pages site and handoff must be regular non-symlink inputs." >&2
  exit 1
fi

site_dir="$(realpath -e -- "$PAGES_SITE_DIR")"
handoff_file="$(realpath -e -- "$PAGES_HANDOFF_FILE")"
provenance_file="$site_dir/.foundation-provenance.json"
source_file="$site_dir/.source-commit"
if [[ ! -f "$provenance_file" ]] ||
  [[ ! -f "$source_file" ]] ||
  [[ -L "$provenance_file" ]] ||
  [[ -L "$source_file" ]]; then
  echo "ERROR: static artifact provenance or source marker is missing." >&2
  exit 1
fi
if find "$site_dir" -type l -print -quit | grep -q .; then
  echo "ERROR: Pages artifact contains a symlink." >&2
  exit 1
fi
if [[ "$(tr -d '\r\n' <"$source_file")" != "$EXPECTED_SOURCE_COMMIT" ]] ||
  [[ "$(jq --raw-output '.sourceCommit // empty' "$provenance_file")" != \
    "$EXPECTED_SOURCE_COMMIT" ]]; then
  echo "ERROR: static artifact source identity does not match approval." >&2
  exit 1
fi
if [[ "$(sha256sum "$provenance_file" | cut -d' ' -f1)" != \
  "$EXPECTED_PROVENANCE_SHA256" ]]; then
  echo "ERROR: static artifact provenance digest does not match approval." >&2
  exit 1
fi
if ! jq --exit-status \
  --arg source "$EXPECTED_SOURCE_COMMIT" \
  --arg provenance "$EXPECTED_PROVENANCE_SHA256" \
  '
    .schemaVersion == "1.0" and
    .status == "prepared-unpublished" and
    .privateSourceCommit == $source and
    .staticProvenanceSha256 == $provenance
  ' "$handoff_file" >/dev/null; then
  echo "ERROR: Pages publication handoff does not match approved inputs." >&2
  exit 1
fi

mapfile -t declared_files < <(
  jq --exit-status --raw-output \
    '.files[] | select(.path != null and .sha256 != null) | [.path, .sha256] | @tsv' \
    "$provenance_file"
)
if (( ${#declared_files[@]} == 0 )); then
  echo "ERROR: static provenance contains no files." >&2
  exit 1
fi
declare -A declared_paths=()
for entry in "${declared_files[@]}"; do
  IFS=$'\t' read -r relative expected_digest <<<"$entry"
  if [[ ! "$relative" =~ ^[A-Za-z0-9._/-]+$ ]] ||
    [[ "$relative" == /* || "$relative" == ./* || "$relative" == */./* ]] ||
    [[ "$relative" == ".." || "$relative" == ../* || "$relative" == */../* ]] ||
    [[ "$relative" == */ || "$relative" == *"//"* ]] ||
    [[ "$relative" == ".git" || "$relative" == .git/* ||
      "$relative" == */.git || "$relative" == */.git/* ]] ||
    [[ "$relative" == ".github" || "$relative" == .github/* ||
      "$relative" == */.github || "$relative" == */.github/* ]] ||
    [[ ! "$expected_digest" =~ ^[0-9a-f]{64}$ ]] ||
    [[ -n "${declared_paths[$relative]:-}" ]]; then
    echo "ERROR: unsafe or duplicate path in static provenance: $relative" >&2
    exit 1
  fi
  declared_paths["$relative"]=1
  artifact_file="$site_dir/$relative"
  if [[ ! -f "$artifact_file" ]] ||
    [[ -L "$artifact_file" ]] ||
    [[ "$(realpath -e -- "$artifact_file")" != "$site_dir/"* ]] ||
    [[ "$(sha256sum "$artifact_file" | cut -d' ' -f1)" != "$expected_digest" ]]; then
    echo "ERROR: static artifact file does not match provenance: $relative" >&2
    exit 1
  fi
done

mapfile -t actual_files < <(
  find "$site_dir" -type f \
    ! -name ".foundation-provenance.json" \
    -printf '%P\n' | sort
)
if (( ${#actual_files[@]} != ${#declared_files[@]} )); then
  echo "ERROR: static artifact file inventory differs from provenance." >&2
  exit 1
fi
for relative in "${actual_files[@]}"; do
  if [[ -z "${declared_paths[$relative]:-}" ]]; then
    echo "ERROR: static artifact contains an undeclared file: $relative" >&2
    exit 1
  fi
done

echo "Verified exact static Pages artifact. No publication or deployment occurred."
