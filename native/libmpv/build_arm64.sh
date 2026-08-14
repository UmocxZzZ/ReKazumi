#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <libmpv-build-root> <rekazumi-root>" >&2
  exit 2
fi

build_root="$(cd "$1" && pwd)"
rekazumi_root="$(cd "$2" && pwd)"
buildscripts="$build_root/buildscripts"

cd "$buildscripts"

./download.sh

install -m 0644 \
  "$rekazumi_root/native/libmpv/patches/mpv/0002-add-rekazumi-vulkan-frame-generation.patch" \
  "$buildscripts/patches/mpv/0002-add-rekazumi-vulkan-frame-generation.patch"

./patch.sh

rm -f scripts/ffmpeg.sh
cp flavors/default.sh scripts/ffmpeg.sh

./build.sh --arch arm64

pushd deps/media-kit-android-helper >/dev/null
chmod +x gradlew
./gradlew assembleRelease
unzip -o app/build/outputs/apk/release/app-release.apk \
  -d app/build/outputs/apk/release/unpacked
cp app/build/outputs/apk/release/unpacked/lib/arm64-v8a/libmediakitandroidhelper.so \
  "$buildscripts/prefix/arm64-v8a/usr/local/lib"
popd >/dev/null

package_root="$buildscripts/package"
rm -rf "$package_root"
mkdir -p "$package_root/lib/arm64-v8a"
cp "$buildscripts"/prefix/arm64-v8a/usr/local/lib/*.so \
  "$package_root/lib/arm64-v8a/"

find "$package_root" -exec touch -d "2025-01-01 00:00:00" {} +

output="$buildscripts/rekazumi-vulkan-framegen-prototype-arm64-v8a.jar"
rm -f "$output"
pushd "$package_root" >/dev/null
find lib/arm64-v8a -type f | sort | zip -r -X "$output" -@
popd >/dev/null

sha256sum "$output"
