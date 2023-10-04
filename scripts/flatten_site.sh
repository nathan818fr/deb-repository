#!/bin/bash
set -Eeuo pipefail
shopt -s inherit_errexit

function main() {
  local site_dir
  site_dir="$(realpath -m "$(dirname "$(realpath -m "$0")")/../site")"

  git -C "$site_dir" update-ref -d HEAD
  git -C "$site_dir" checkout --orphan site
  git -C "$site_dir" add --all
  git -C "$site_dir" commit -am 'update'
  git -C "$site_dir" push --force
}

main "$@"
exit "$?"
