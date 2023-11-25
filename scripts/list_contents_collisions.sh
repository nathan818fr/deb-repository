#!/bin/bash
set -Eeuo pipefail
shopt -s inherit_errexit

function main() {
  python3 - debian:<(get_debian_contents) nathan818fr:<(get_site_contents) << 'EOF'
import sys

any_contents = {}
for arg in sys.argv[1:]:
  repo_name, repo_contents_path = arg.split(':', 1)
  repo_contents = {}
  with open(repo_contents_path) as f:
    for line in f:
      pkg_file, pkg_name = line.rstrip().rsplit(None, 1)
      repo_contents.setdefault(pkg_file, pkg_name)
  for pkg_file, pkg_name in repo_contents.items():
    any_contents.setdefault(pkg_file, []).append(f'{repo_name}/{pkg_name.split("/")[-1]}')

collisions = {}
for pkg_file, pkg_names in any_contents.items():
  if len(pkg_names) > 1:
    collisions.setdefault(f'{", ".join(pkg_names)}', []).append(pkg_file)

for pkg_names, pkg_files in collisions.items():
  print(f'{pkg_names}:')
  for pkg_file in pkg_files:
    print(f'  {pkg_file}')
EOF
}

function get_site_contents() {
  local site_dir
  site_dir="$(realpath -m "$(dirname "$(realpath -m "$0")")/../site")"

  cat "${site_dir}/dists/stable/main/Contents-amd64"
}

function get_debian_contents() {
  curl -fsSL "https://deb.debian.org/debian/dists/stable/main/Contents-all.gz" | gunzip
  curl -fsSL "https://deb.debian.org/debian/dists/stable/main/Contents-amd64.gz" | gunzip
  curl -fsSL "https://deb.debian.org/debian/dists/stable/contrib/Contents-all.gz" | gunzip
  curl -fsSL "https://deb.debian.org/debian/dists/stable/contrib/Contents-amd64.gz" | gunzip
  curl -fsSL "https://deb.debian.org/debian/dists/stable/non-free/Contents-all.gz" | gunzip
  curl -fsSL "https://deb.debian.org/debian/dists/stable/non-free/Contents-amd64.gz" | gunzip
  curl -fsSL "https://deb.debian.org/debian/dists/stable/non-free-firmware/Contents-all.gz" | gunzip
  curl -fsSL "https://deb.debian.org/debian/dists/stable/non-free-firmware/Contents-amd64.gz" | gunzip
}

main "$@"
exit "$?"
