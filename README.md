# Nextcloud OpenProject Integration Builds

This repository publishes prebuilt artifacts for `nextcloud/integration_openproject` `release/*` branches.

## How it works

A scheduled workflow (`.github/workflows/build-release-channels.yml`) runs every 5 minutes and:

1. Reads upstream `release/*` branch heads.
2. Compares each branch head to `channels/<branch-slug>.env` (`SOURCE_COMMIT`).
3. Builds changed branches with `npm ci` and `npm run build`.
4. Publishes a GitHub Release with:
   - `integration_openproject-<branch-slug>-<sha7>.tar.gz`
   - `integration_openproject-<branch-slug>-<sha7>.tar.gz.sha256`
5. Updates `channels/<branch-slug>.env` to point to the newest successful artifact.

## Channel file format

Example: `channels/release-2.10.env`

```env
SOURCE_REPO=nextcloud/integration_openproject
SOURCE_BRANCH=release/2.10
SOURCE_COMMIT=<40-char-sha>
BUILD_TAG=build-release-2.10-<timestamp>-<sha7>
ASSET_NAME=integration_openproject-release-2.10-<sha7>.tar.gz
ASSET_URL=https://github.com/opf/nextcloud-integration-openproject-builds/releases/download/<tag>/<asset>
ASSET_SHA256=<sha256>
BUILT_AT=<iso8601-utc>
```

These channel files are consumed by `saas-deploy` Nextcloud integration updater sidecars.
