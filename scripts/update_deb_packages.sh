#!/bin/bash
set -Eeuo pipefail
shopt -s inherit_errexit

function main() {
  SUPPORTED_ARCHS=(all amd64 arm64)
  SITE_DIR="$(realpath -m "$(dirname "$(realpath -m "$0")")/../site")"

  # Create a temporary directory that will be automatically deleted on exit
  TEMP_DIR="$(umask 077 > /dev/null && realpath -m "$(mktemp -d)")"
  if [[ -d "$TEMP_DIR" ]]; then
    function cleanup_TEMP_DIR() { rm -rf "$TEMP_DIR"; }
    trap cleanup_TEMP_DIR INT TERM EXIT
  fi

  # Update the packages
  download_nathan818_packages
  download_latest_gh_release dive wagoodman/dive
  download_latest_gh_release gh cli/cli
  download_latest_gh_release glow charmbracelet/glow
  download_latest_gh_release mmdbinspect maxmind/mmdbinspect
  download_latest_gh_release sops mozilla/sops
  download_latest_gh_release ulauncher Ulauncher/Ulauncher
  download_latest_gh_release xclicker robiot/xclicker
  download_latest_gh_release yaru818-theme nathan818fr/yaru818
}

function download_nathan818_packages() {
  local packages
  packages="$(
    gh_curl -fsSL "https://api.github.com/repos/nathan818fr/deb-packages/releases/tags/latest" \
      | jq -Mr '.assets[] | select(.name | endswith(".deb")) | "\(.created_at)\t\(.name)\t\(.browser_download_url)"' \
      | LANG=C sort -r
  )"

  declare -A downloaded_packages
  local pkg_filename pkg_url pkg_name pkg_version pkg_arch
  while IFS=$'\t' read -rd $'\n' _ pkg_filename pkg_url; do
    IFS=_ read -r pkg_name pkg_version pkg_arch _ <<< "${pkg_filename:0:-4}"

    if [[ -n "${downloaded_packages[${pkg_name}_${pkg_arch}]:-}" ]]; then continue; fi
    downloaded_packages["${pkg_name}_${pkg_arch}"]=1

    download_deb "$pkg_name" "$pkg_version" "$pkg_arch" "$pkg_url"
  done <<< "$packages"
}

function download_latest_gh_release() {
  local pkg_name repo
  pkg_name="$1"
  repo="$2"

  printf 'Fetching latest release of %s ...\n' "$repo"
  local release_meta
  release_meta="$(gh_curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")"

  local pkg_version
  pkg_version="$(jq -Mr '.tag_name' <<< "$release_meta")"
  if [[ "$pkg_version" =~ ^v[^a-z] ]]; then
    pkg_version="${pkg_version:1}"
  fi

  local pkg_arch pkg_url pkgs_count=0
  for pkg_arch in "${SUPPORTED_ARCHS[@]}"; do
    pkg_url="$(jq -Mr --arg pkg_arch "$pkg_arch" \
      '.assets[] | select(.name|endswith("_\($pkg_arch).deb")) | .browser_download_url' \
      <<< "$release_meta")"
    if [[ -z "$pkg_url" ]]; then continue; fi

    pkgs_count=$((pkgs_count + 1))
    download_deb "$pkg_name" "$pkg_version" "$pkg_arch" "$pkg_url"
  done

  if [[ "$pkgs_count" -eq 0 ]]; then
    printf 'error: no packages found for %s\n' "$pkg_name" >&2
    return 1
  fi
}

function download_deb() {
  local pkg_name pkg_version pkg_arch pkg_url
  pkg_name="$1"
  pkg_version="$2"
  pkg_arch="$3"
  pkg_url="$4"

  validate_pkg_name "$pkg_name"
  validate_pkg_version "$pkg_version"
  validate_pkg_arch "$pkg_arch"

  # If the package already exists, don't download it again
  local pkg_filename="${pkg_name}_${pkg_version}_${pkg_arch}.deb"
  local pkg_filepath="${SITE_DIR}/pool/stable/main/${pkg_filename}"
  if [[ -e "$pkg_filepath" ]]; then
    printf '✅ %s already exists\n' "$pkg_filename"
    return 0
  fi

  # Download the package
  printf 'Downloading %s ...\n' "$pkg_filename"
  curl -fL# -o "${TEMP_DIR}/${pkg_filename}" -- "$pkg_url"

  # Move the downloaded package to the site directory, replacing previous versions
  mkdir -p -- "$(dirname "$pkg_filepath")"
  find "$(dirname "$pkg_filepath")" -name "${pkg_name}_*_${pkg_arch}.deb" -exec rm -vf {} \;
  mv -T -- "${TEMP_DIR}/${pkg_filename}" "$pkg_filepath"
  printf '⬆️ %s was downloaded\n' "$pkg_filename"
}

function validate_pkg_name() {
  local pkg_name
  pkg_name="$1"

  if [[ ! "$pkg_name" =~ ^[a-z0-9-]+$ ]]; then
    printf "error: '%s' is not a valid package name\n" "$pkg_name" >&2
    return 1
  fi
}

function validate_pkg_version() {
  local pkg_version
  pkg_version="$1"

  if [[ ! "$pkg_version" =~ ^[a-zA-Z0-9.:~+-]+$ ]]; then
    printf "error: '%s' is not a valid package version\n" "$pkg_version" >&2
    return 1
  fi
}

function validate_pkg_arch() {
  local pkg_arch
  pkg_arch="$1"

  if [[ ! "$pkg_arch" =~ ^[a-z0-9]+$ ]]; then
    printf "error: '%s' is not a valid package arch\n" "$pkg_arch" >&2
    return 1
  fi
}

function gh_curl() {
  curl -H 'Authorization: Basic Og==' "$@"
}

main "$@"
exit "$?"
