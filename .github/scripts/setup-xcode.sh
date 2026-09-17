#!/bin/bash
set -euo pipefail

xcode_build=27B5019j
xcode_dir="$HOME/Library/Caches/lattice-xcode/$xcode_build"
xcodes_dir="$RUNNER_TEMP/xcodes"
mkdir -p "$xcode_dir" "$xcodes_dir"

curl --fail --location --silent --show-error --retry 3 \
  https://github.com/XcodesOrg/xcodes/releases/download/2.1.0/xcodes.zip \
  --output "$xcodes_dir/xcodes.zip"
printf '%s  %s\n' \
  f1519afe934a513e85dd9b32fc872394becbbb6a41db15d9ac3926a09a891888 \
  "$xcodes_dir/xcodes.zip" | shasum -a 256 --check
ditto -x -k "$xcodes_dir/xcodes.zip" "$xcodes_dir"

if ! xcode_path="$("$xcodes_dir/xcodes" installed 27.2 --directory "$xcode_dir" 2>/dev/null)"; then
  : "${FASTLANE_SESSION:?Set the FASTLANE_SESSION repository secret to download Xcode.}"
  "$xcodes_dir/xcodes" install '27.2 Beta' \
    --directory "$xcode_dir" \
    --use-fastlane-auth --update --empty-trash --no-superuser < /dev/null
  xcode_path="$("$xcodes_dir/xcodes" installed 27.2 --directory "$xcode_dir")"
fi

installed_build="$(plutil -extract ProductBuildVersion raw -o - "$xcode_path/Contents/version.plist")"
if [[ "$installed_build" != "$xcode_build" ]]; then
  echo "::error::Expected Xcode build $xcode_build, but found $installed_build."
  exit 1
fi

export DEVELOPER_DIR="$xcode_path/Contents/Developer"
echo "DEVELOPER_DIR=$DEVELOPER_DIR" >> "$GITHUB_ENV"
sudo -n xcode-select --switch "$DEVELOPER_DIR"
sudo -n xcodebuild -license accept
sudo -n xcodebuild -runFirstLaunch
xcodebuild -version
