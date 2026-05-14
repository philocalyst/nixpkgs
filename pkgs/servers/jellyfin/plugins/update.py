#!/usr/bin/env python3

import json
import urllib.request
import subprocess
import os
import sys

MANIFEST_URL = "https://repo.jellyfin.org/releases/plugin/manifest.json"

def prefetch_url(url):
    try:
        result = subprocess.run(
            ["nix-prefetch-url", "--unpack", url],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Failed to prefetch {url}: {e.stderr}", file=sys.stderr)
        return None

def main():
    try:
        req = urllib.request.Request(MANIFEST_URL, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response:
            manifest = json.loads(response.read().decode())
    except Exception as e:
        print(f"Failed to fetch manifest: {e}", file=sys.stderr)
        sys.exit(1)

    # In nixpkgs, jellyfin version needs to be determined. Let's just hardcode or read from jellyfin attr.
    # We will assume we can get it from the environment if update.sh runs it, or run nix-instantiate.
    try:
        jellyfin_version = subprocess.run(
            ["nix-instantiate", "--eval", "-E", "(import ../../../.. {}).jellyfin.version", "--json"],
            stdout=subprocess.PIPE, text=True, check=True
        ).stdout.strip().strip('"')
    except Exception as e:
        print("Failed to get jellyfin version, using default 10.9.11", file=sys.stderr)
        jellyfin_version = "10.9.11"

    # Jellyfin ABI is usually "10.9" instead of "10.9.11"
    parts = jellyfin_version.split('.')
    if len(parts) >= 2:
        abi_version = f"{parts[0]}.{parts[1]}"
    else:
        abi_version = jellyfin_version

    print(f"Detected Jellyfin version: {jellyfin_version} (ABI: {abi_version})")

    generated = {}
    
    for plugin in manifest:
        name = plugin.get("name")
        guid = plugin.get("guid")
        versions = plugin.get("versions", [])
        
        # find highest version matching targetAbi = abi_version
        compatible_versions = []
        for v in versions:
            target_abi = v.get("targetAbi", "")
            # targetAbi sometimes has ".0" etc.
            if target_abi.startswith(abi_version):
                compatible_versions.append(v)
        
        if not compatible_versions:
            continue
            
        # grab the latest compatible version
        # assume they are sorted or simply grab first
        v = compatible_versions[0]
        
        source_url = v.get("sourceUrl")
        if not source_url:
            continue
            
        print(f"Processing {name} {v.get('version')}...")
        hash_val = None
        if os.path.exists("generated.json"):
            with open("generated.json") as f:
                old_gen = json.load(f)
                if name in old_gen and old_gen[name]["version"] == v.get("version"):
                    hash_val = old_gen[name].get("hash")
        
        if not hash_val:
            print(f"Prefetching {source_url}...")
            hash_val = prefetch_url(source_url)
            
        if not hash_val:
            continue
            
        generated[name] = {
            "pname": name.lower().replace(" ", "-"),
            "version": v.get("version"),
            "url": source_url,
            "hash": hash_val,
            "description": plugin.get("description"),
            "owner": plugin.get("owner")
        }

    with open("generated.json", "w") as f:
        json.dump(generated, f, indent=2, sort_keys=True)
        f.write("\n")

if __name__ == "__main__":
    main()
