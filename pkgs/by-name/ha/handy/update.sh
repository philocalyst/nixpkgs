#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update nix gnused gnugrep gawk coreutils git
# shellcheck shell=bash

# 1. `nix-update handy` bumps version, src.hash, cargoHash.
# 2. On a version bump, all frontendDepsHashes entries are reset to lib.fakeHash.
# 3. Rebuilds handy.passthru.frontendDeps to capture the real hash for the current host.
# 4. Remaining entries stay lib.fakeHash — re-run on each target host to fill them in.

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
pkg_file="$repo_root/pkgs/by-name/ha/handy/package.nix"
cd "$repo_root"

if [[ ! -f "$pkg_file" ]]; then
  echo "update.sh: $pkg_file not found" >&2
  exit 1
fi

read_version() {
  sed -n 's|^\s*version = "\([^"]*\)";.*|\1|p' "$pkg_file" | head -n1
}

nix_update_args=(handy)
if [[ $# -gt 0 ]]; then
  nix_update_args+=(--version "$1")
fi

old_version=$(read_version)
nix-update "${nix_update_args[@]}"
new_version=$(read_version)

if [[ "$old_version" != "$new_version" ]]; then
  echo "update.sh: version bump $old_version → $new_version; resetting frontendDepsHashes"
  sed -i -e '/frontendDepsHashes = {/,/^    };$/ s|"sha256-[^"]*"|lib.fakeHash|g' "$pkg_file"
fi

system=$(nix --extra-experimental-features nix-command eval --impure --raw --expr 'builtins.currentSystem')

# Force lib.fakeHash so the build reports the real hash via "got:" even
# when the existing value happens to still be correct.
sed -i "s|\"$system\" = \"sha256-[^\"]*\";|\"$system\" = lib.fakeHash;|" "$pkg_file"

if ! grep -q "\"$system\" = lib.fakeHash;" "$pkg_file"; then
  echo "update.sh: no frontendDepsHashes entry for $system to refresh" >&2
  exit 1
fi

echo "update.sh: rebuilding frontendDeps on $system"
build_out=$(nix-build -A handy.passthru.frontendDeps --no-out-link 2>&1 || true)
new_hash=$(awk '/got:/ { print $2; exit }' <<<"$build_out")
if [[ -z "${new_hash:-}" ]]; then
  echo "update.sh: failed to parse the new hash from nix-build output" >&2
  printf '%s\n' "$build_out" | tail -n40 >&2
  exit 1
fi

sed -i "s|\"$system\" = lib.fakeHash;|\"$system\" = \"$new_hash\";|" "$pkg_file"

echo "update.sh: $system → $new_hash"
if [[ "$old_version" != "$new_version" ]]; then
  echo "update.sh: other frontendDepsHashes entries are still lib.fakeHash;"
  echo "update.sh: re-run on each target host to fill them in."
fi
