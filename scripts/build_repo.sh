#!/bin/bash
set -Eeuo pipefail
shopt -s inherit_errexit

function main() {
  local signing_key site_dir distributions components archs
  signing_key='nathan818 Debian Repository Signing Key <deb-repo@nathan818.fr>'
  site_dir="$(realpath -m "$(dirname "$(realpath -m "$0")")/../site")"
  distributions=(stable)
  components=(main)
  archs=(all amd64 arm64)

  pushd "$site_dir" > /dev/null
  local pool_dir dist_dir arch_dist_dir release_file
  for distribution in "${distributions[@]}"; do
    for component in "${components[@]}"; do
      pool_dir="pool/${distribution}/${component}"
      dist_dir="dists/${distribution}/${component}"

      for arch in "${archs[@]}"; do
        # Generate Packages and Contents indexes
        arch_dist_dir="${dist_dir}/binary-${arch}"
        mkdir -p -- "$arch_dist_dir"

        printf "Generating Packages index for %s/%s/%s ...\n" "$distribution" "$component" "$arch"
        apt-ftparchive -a "$arch" packages "$pool_dir" > "${arch_dist_dir}/Packages"

        printf "Generating Contents index for %s/%s/%s ...\n" "$distribution" "$component" "$arch"
        apt-ftparchive -a "$arch" contents "$pool_dir" > "${dist_dir}/Contents-${arch}"
      done

      # Compress indexes
      printf 'Compressing indexes for %s/%s ...\n' "$distribution" "$component"
      find "dists/${distribution}" \! -name '*.gz' -a \( -name 'Packages' -o -name 'Contents-*' \) -exec gzip -f -k6 {} \;

      # Generate Release file
      printf 'Generating Release file for %s/%s ...\n' "$distribution" "$component"
      release_file="dists/${distribution}/Release"
      apt-ftparchive \
        -o "APT::FTPArchive::Release::Codename=${distribution}" \
        -o "APT::FTPArchive::Release::Architectures=${archs[*]}" \
        release "dists/${distribution}" > "$release_file"

      # Sign Release file + Generate InRelease
      gpg -sba --default-key "$signing_key" < "$release_file" > "${release_file}.gpg"
      gpg -sba --default-key "$signing_key" --clearsign < "$release_file" > "dists/${distribution}/InRelease"
    done
  done
}

main "$@"
exit "$?"
