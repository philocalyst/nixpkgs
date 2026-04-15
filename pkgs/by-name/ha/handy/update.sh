#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-update nix gnused gnugrep gawk coreutils git
# shellcheck shell=bash

# update.sh — refresh Handy version, src hash, cargoHash, and the
# `frontendDepsHashes` entry for the host this script runs on.
#
# Usage:
#   nix-shell maintainers/scripts/update.nix --argstr package handy
#   # or manually, from the nixpkgs root:
#   ./pkgs/by-name/ha/handy/update.sh           # follow upstream latest
#   ./pkgs/by-name/ha/handy/update.sh 0.8.3     # pin an explicit version
#
# What it does:
#   1. `nix-update handy` bumps `version`, `src.hash`, `cargoHash`.
#   2. On a version bump, *all* `frontendDepsHashes` entries are reset
#      to `lib.fakeHash` so stale values from the previous release
#      cannot silently pass a hash check on a host where we do not
#      rebuild.
#   3. `handy.passthru.frontendDeps` is rebuilt to capture the real
#      hash for the current host's system; that entry is rewritten
#      from `lib.fakeHash` back to the real value.
#   4. The remaining entries stay `lib.fakeHash`. Re-run the script on
#      each target host (or over a remote builder) to fill them in;
#      attempts to build handy on those hosts until then will fail
#      loudly on the hash mismatch rather than silently using stale
#      data.

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
  echo "update.sh: version bump $old_version → $new_version; resetting stale frontendDepsHashes"
  # Operate only on lines inside the `frontendDepsHashes = { ... };` block.
  sed -i -e '/frontendDepsHashes = {/,/^    };$/ s|"sha256-[^"]*"|lib.fakeHash|g' "$pkg_file"
fi

system=$(nix --extra-experimental-features nix-command eval --impure --raw --expr 'builtins.currentSystem')

# Force the current host's entry to lib.fakeHash so the next build
# reports the real value via the "got:" diagnostic even if it happens
# to still match the previous one.
sed -i "s|\"$system\" = \"sha256-[^\"]*\";|\"$system\" = lib.fakeHash;|" "$pkg_file"

if ! grep -q "\"$system\" = lib.fakeHash;" "$pkg_file"; then
  echo "update.sh: no frontendDepsHashes entry for $system to refresh" >&2
  exit 1
fi

echo "update.sh: rebuilding handy.passthru.frontendDeps on $system to capture the new hash"
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
