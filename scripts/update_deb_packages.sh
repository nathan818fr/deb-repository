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
  download_latest_gh_release bruno usebruno/bruno
  download_latest_gh_release dive wagoodman/dive
  download_latest_gh_release gh cli/cli
  download_latest_gh_release glow charmbracelet/glow
  download_latest_gh_release mmdbinspect maxmind/mmdbinspect
  download_latest_gh_release rclone rclone/rclone dash
  download_latest_gh_release sops mozilla/sops
  download_latest_gh_release ulauncher Ulauncher/Ulauncher
  download_latest_gh_release xclicker robiot/xclicker
  download_latest_gh_release yaru818-theme nathan818fr/yaru818
  download_from_apt onedrive https://download.opensuse.org/repositories/home:/npreining:/debian-ubuntu-onedrive/Debian_12 Packages
  download_from_apt ngrok https://ngrok-agent.s3.amazonaws.com dists/bullseye/main/binary-{amd64,arm64}/Packages
  download_from_apt tuxedo-drivers,tuxedo-keyboard,tuxedo-control-center,tuxedo-dgpu-run https://deb.tuxedocomputers.com/ubuntu dists/jammy/main/binary-amd64/Packages
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
  local pkg_name repo format
  pkg_name="$1"
  repo="$2"
  format="${3:-standard}"

  printf 'Fetching latest release of %s ...\n' "$repo"
  local release_meta
  release_meta="$(gh_curl -fsSL "https://api.github.com/repos/${repo}/releases/latest")"

  local pkg_version
  pkg_version="$(jq -Mr '.tag_name' <<< "$release_meta")"
  if [[ "$pkg_version" =~ ^v[^a-z] ]]; then
    pkg_version="${pkg_version:1}"
  fi

  local pkg_arch pkg_pattern pkg_url pkgs_count=0
  for pkg_arch in "${SUPPORTED_ARCHS[@]}"; do
    case "$format" in
      standard) pkg_pattern="${pkg_name}_[^_]+_(linux_)?${pkg_arch}(_linux)?\.deb" ;;
      dash) pkg_pattern="${pkg_name}-[^-]+-(linux-)?${pkg_arch}(-linux)?\.deb" ;;
      *)
        printf 'error: unknown format: %s\n' "$format" >&2
        return 1
        ;;
    esac
    pkg_url="$(jq -Mr --arg pkg_pattern "$pkg_pattern" \
      '.assets[] | select(.name|test("^\($pkg_pattern)$")) | .browser_download_url' \
      <<< "$release_meta")"
    if [[ -z "$pkg_url" ]]; then continue; fi

    download_deb "$pkg_name" "$pkg_version" "$pkg_arch" "$pkg_url"
    pkgs_count=$((pkgs_count + 1))
  done

  if [[ "$pkgs_count" -eq 0 ]]; then
    printf 'error: no packages found for %s\n' "$pkg_name" >&2
    return 1
  fi
}

function download_from_apt() {
  local pkg_names repo_url repo_packages_files
  pkg_names="$1"
  repo_url="$2"
  shift 2
  repo_packages_files=("$@")

  printf 'Fetching Packages files from %s ...\n' "$repo_url"
  local repo_packages_file repo_packages=''
  for repo_packages_file in "${repo_packages_files[@]}"; do
    repo_packages+="$(curl -fsSL -- "${repo_url}/${repo_packages_file}")"$'\n\n'
  done
  repo_packages="$(parse_deb_packages_index <<< "$repo_packages")"

  for pkg_name in ${pkg_names//,/ }; do
    local pkgs_count=0
    for pkg_arch in "${SUPPORTED_ARCHS[@]}"; do
      local pkg_params
      pkg_params="$(
        jq <<< "$repo_packages" -Mr \
          --arg pkg_name "$pkg_name" \
          --arg pkg_arch "$pkg_arch" \
          '.[] | select(.Package == $pkg_name and .Architecture == $pkg_arch) | "\(.Version)\t\(.Filename)"' \
          | LANG=C sort -rV | head -n1
      )"
      if [[ -z "$pkg_params" ]]; then continue; fi

      IFS=$'\t' read -r pkg_version pkg_url <<< "$pkg_params"
      pkg_url="${repo_url}/${pkg_url}"

      download_deb "$pkg_name" "$pkg_version" "$pkg_arch" "$pkg_url"
      pkgs_count=$((pkgs_count + 1))
    done

    if [[ "$pkgs_count" -eq 0 ]]; then
      printf 'error: no packages found for %s\n' "$pkg_name" >&2
      return 1
    fi
  done
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

function parse_deb_packages_index() {
  # Note: multi-line fields are not supported, only the first line is kept
  python3 -c '
import sys, json
stdin = sys.stdin.read()
stdin = stdin.replace("\r\n", "\n")
packages = []
for package_raw in stdin.split("\n\n"):
  if package_raw:
    package = {}
    for field_raw in package_raw.split("\n"):
      if field_raw.startswith(" "):
        continue
      field = field_raw.rstrip().split(": ", 1)
      if len(field) == 2:
        package[field[0]] = field[1]
    packages.append(package)
print(json.dumps(packages, indent=2))
'
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
