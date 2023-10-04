#!/bin/bash
set -Eeuo pipefail
shopt -s inherit_errexit

function main() {
  local site_dir origin
  site_dir="$(realpath -m "$(dirname "$(realpath -m "$0")")/../site")"
  origin="$(git remote get-url origin)"

  mkdir -p -- "$site_dir"
  git -C "$site_dir" init --quiet
  git -C "$site_dir" config core.hooksPath /dev/null
  git -C "$site_dir" remote add origin -- "$origin" 2> /dev/null || git -C "$site_dir" remote set-url origin -- "$origin"
  git -C "$site_dir" fetch -- origin site
  git -C "$site_dir" reset --hard origin/site
  git -C "$site_dir" checkout site
  git -C "$site_dir" branch --set-upstream-to=origin/site site
}

main "$@"
exit "$?"
