#!/usr/bin/env bash

set -eu


RE_VERSION="^[0-9]+\.[0-9]+(\.[0-9]+)?(\.[0-9]+)?$"

function check_version_formatting() {
  if [[ ! "${1}" =~ $RE_VERSION ]];
  then
    echo "ERROR: version number is not correctly formatted: ${1}"
    exit 1
  fi
}

function format_version() {
  ver=$1

  # The number of iterations to perform is 3 (the maximum occurences of '.' in
  # a version string) minus the number of occurences of '.' already present in
  # the version string.
  res=${ver//[^.]}
  iters=$((3 - ${#res}))

  # Append '.0' to the version string $iters number of times to create a
  # version string which matches the release tags.
  for ((i = 0; i < iters; i++));
  do
    ver="${ver}.0"
  done

  echo "$ver"
}

function latest_version() {
  curl -s https://api.github.com/repos/esp-rs/rust-build/releases \
    | jq -r "map(select(.prerelease | not)) | map(.tag_name) | first" \
    | sed -e "s/^v//"
}


# Download and execute the installation script from the esp-rs/rust-build
# repository: https://github.com/esp-rs/rust-build
#
# This installs not only the Rust compiler fork with support for the Xtensa
# architecture but also the required Xtensa toolchain binaries. We save the
# required exports to a file for later processing, to handle around some
# weirdness with GitHub runners (see below for details). If a version number
# formatted following (our extended version of) semver is provided, attempt to
# install that version of the compiler.

crates="${1:-}"
version="${2:-latest}"
buildtargets="${3:-all}"

case $version in
  latest)
    version=$(latest_version)
    ;;

  *)
    version=$(format_version "$version")
    ;;
esac

check_version_formatting "$version"

curl \
  -L "https://github.com/esp-rs/rust-build/releases/download/v$version/install-rust-toolchain.sh" \
  -o "$HOME/install-rust-toolchain.sh"

chmod +x "$HOME/install-rust-toolchain.sh"

function install_rust_toolchain() {
  "$HOME/install-rust-toolchain.sh" \
    --export-file "$HOME/exports" \
    --extra-crates "$crates" \
    --build-target "${buildtargets}" \
    "@"
}

case $version in
  latest)
    install_rust_toolchain
    ;;

  *)
    install_rust_toolchain --toolchain-version "$version"
    ;;
esac


# With the required exports specified by the rust-build installation script
# saved to a file, we can simply `source` it to export said variables. GitHub
# runners are a bit strange, however, in that we need to update the
# `$GITHUB_PATH` variable instead of `$PATH` as we normally would. More details
# see: https://stackoverflow.com/a/68214331

#shellcheck source=/dev/null
source "$HOME/exports"
echo "$PATH" >> "$GITHUB_PATH"
echo "LIBCLANG_PATH=${LIBCLANG_PATH}" >> "$GITHUB_ENV"
