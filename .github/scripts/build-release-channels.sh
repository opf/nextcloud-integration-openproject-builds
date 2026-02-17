#!/usr/bin/env bash

set -euo pipefail

UPSTREAM_REPO_URL=${UPSTREAM_REPO_URL:-https://github.com/nextcloud/integration_openproject.git}
SOURCE_REPO_LABEL=${SOURCE_REPO_LABEL:-nextcloud/integration_openproject}
CHANNELS_DIR=${CHANNELS_DIR:-channels}

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required"
  exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required"
  exit 1
fi

if [ -z "${GITHUB_REPOSITORY:-}" ]; then
  echo "GITHUB_REPOSITORY is required"
  exit 1
fi

mkdir -p "$CHANNELS_DIR"

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

mapfile -t release_refs < <(git ls-remote --heads "$UPSTREAM_REPO_URL" 'refs/heads/release/*' | sort -k2)

if [ "${#release_refs[@]}" -eq 0 ]; then
  echo "No upstream release branches found"
  exit 0
fi

channels_changed=0
branches_failed=0

process_branch() {
  local ref_line=$1
  local source_commit source_ref source_branch branch_slug channel_file current_commit
  local work_dir stage_dir node_engine sha7 timestamp built_at build_tag
  local asset_name checksum_name asset_path checksum_path asset_sha256 asset_url

  source_commit=$(echo "$ref_line" | awk '{print $1}')
  source_ref=$(echo "$ref_line" | awk '{print $2}')
  source_branch=${source_ref#refs/heads/}
  branch_slug=${source_branch//\//-}
  channel_file="$CHANNELS_DIR/$branch_slug.env"

  current_commit=""
  if [ -f "$channel_file" ]; then
    current_commit=$(grep -E '^SOURCE_COMMIT=' "$channel_file" | head -n 1 | cut -d '=' -f 2- || true)
  fi

  if [ "$source_commit" = "$current_commit" ]; then
    echo "[$source_branch] already up to date at $source_commit"
    return 0
  fi

  work_dir="$tmp_root/work-$branch_slug"
  stage_dir="$tmp_root/stage-$branch_slug"

  rm -rf "$work_dir" "$stage_dir"

  echo "[$source_branch] building commit $source_commit"

  git clone --depth 1 --branch "$source_branch" "$UPSTREAM_REPO_URL" "$work_dir"

  node_engine=$(jq -r '.engines.node // "22"' "$work_dir/package.json")
  echo "[$source_branch] package.json engines.node=$node_engine"

  (
    cd "$work_dir"
    npm ci
    npm run build
  )

  sha7=${source_commit:0:7}
  timestamp=$(date -u +"%Y%m%dT%H%M%SZ")
  built_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  build_tag="build-${branch_slug}-${timestamp}-${sha7}"
  asset_name="integration_openproject-${branch_slug}-${sha7}.tar.gz"
  checksum_name="${asset_name}.sha256"

  asset_path="$tmp_root/$asset_name"
  checksum_path="$tmp_root/$checksum_name"

  mkdir -p "$stage_dir/integration_openproject"

  rsync -a \
    --exclude '.git' \
    --exclude '.github' \
    --exclude 'node_modules' \
    "$work_dir/" "$stage_dir/integration_openproject/"

  tar -C "$stage_dir" -czf "$asset_path" integration_openproject

  asset_sha256=$(sha256sum "$asset_path" | awk '{print $1}')
  printf '%s\n' "$asset_sha256" > "$checksum_path"

  gh release create "$build_tag" "$asset_path" "$checksum_path" \
    --repo "$GITHUB_REPOSITORY" \
    --title "$build_tag" \
    --notes "Automated build for ${source_branch} at ${source_commit}"

  asset_url="https://github.com/${GITHUB_REPOSITORY}/releases/download/${build_tag}/${asset_name}"

  cat > "$channel_file" <<EOF
SOURCE_REPO=$SOURCE_REPO_LABEL
SOURCE_BRANCH=$source_branch
SOURCE_COMMIT=$source_commit
BUILD_TAG=$build_tag
ASSET_NAME=$asset_name
ASSET_URL=$asset_url
ASSET_SHA256=$asset_sha256
BUILT_AT=$built_at
EOF

  channels_changed=1
  echo "[$source_branch] channel updated to $source_commit"
}

for ref_line in "${release_refs[@]}"; do
  if ! process_branch "$ref_line"; then
    branches_failed=1
    echo "Failed to build/publish branch from ref: $ref_line" >&2
    continue
  fi
done

if [ "$channels_changed" -eq 0 ]; then
  echo "No channel updates required"
  if [ "$branches_failed" -ne 0 ]; then
    exit 1
  fi
  exit 0
fi

git add "$CHANNELS_DIR"/*.env

if git diff --cached --quiet; then
  echo "No channel file changes to commit"
  if [ "$branches_failed" -ne 0 ]; then
    exit 1
  fi
  exit 0
fi

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'

git commit -m 'Update integration release channels'
git push

if [ "$branches_failed" -ne 0 ]; then
  echo "At least one branch failed to build/publish" >&2
  exit 1
fi
