#!/usr/bin/env bash
set -Eeuo pipefail
shopt -s inherit_errexit

function main() {
  local repo_name signing_key site_dir distributions components archs
  repo_name='nathan818fr'
  signing_key='nathan818 Debian Repository Signing Key <deb-repo@nathan818.fr>'
  site_dir="$(realpath -m -- "$(dirname -- "$(realpath -m -- "$0")")/../site")"
  distributions=(stable)
  components=(main)
  archs=(all amd64 arm64)

  # Loop through distributions components
  pushd "$site_dir" > /dev/null
  local distribution component pool_dir dist_dir arch arch_dist_dir release_file
  for distribution in "${distributions[@]}"; do
    for component in "${components[@]}"; do
      pool_dir="pool/${distribution}/${component}"
      dist_dir="dists/${distribution}/${component}"

      # Generate Packages and Contents indexes for each arch
      for arch in "${archs[@]}"; do
        arch_dist_dir="${dist_dir}/binary-${arch}"
        mkdir -p -- "$arch_dist_dir"

        printf "Generating Packages index for %s/%s/%s ...\n" "$distribution" "$component" "$arch"
        apt-ftparchive -a "$arch" packages -- "$pool_dir" > "${arch_dist_dir}/Packages"

        printf "Generating Contents index for %s/%s/%s ...\n" "$distribution" "$component" "$arch"
        apt-ftparchive -a "$arch" contents -- "$pool_dir" > "${dist_dir}/Contents-${arch}"
      done

      # Compress indexes
      printf 'Compressing indexes for %s/%s ...\n' "$distribution" "$component"
      find "dists/${distribution}" \! -name '*.gz' -a \( -name 'Packages' -o -name 'Contents-*' \) -exec gzip -f -k6 {} \;

      # Generate Release file
      printf 'Generating Release file for %s/%s ...\n' "$distribution" "$component"
      release_file="dists/${distribution}/Release"
      apt-ftparchive \
        -o "APT::FTPArchive::Release::Origin=${repo_name}" \
        -o "APT::FTPArchive::Release::Label=${repo_name}" \
        -o "APT::FTPArchive::Release::Suite=${distribution}" \
        -o "APT::FTPArchive::Release::Codename=${distribution}" \
        -o "APT::FTPArchive::Release::Components=${components[*]}" \
        -o "APT::FTPArchive::Release::Architectures=${archs[*]}" \
        release -- "dists/${distribution}" \
        | sed '/^Architectures: /a No-Support-for-Architecture-all: Packages' > "$release_file"

      # Sign Release file + Generate InRelease
      gpg -sba --default-key "$signing_key" < "$release_file" > "${release_file}.gpg"
      gpg -sba --default-key "$signing_key" --clearsign < "$release_file" > "dists/${distribution}/InRelease"
    done
  done
}

eval 'main "$@";exit "$?"'
