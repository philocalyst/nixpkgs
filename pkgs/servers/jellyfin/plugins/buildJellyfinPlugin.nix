{
  lib,
  stdenvNoCC,
  unzip,
}:

{
  pname,
  version,
  src,
  meta ? { },
  ...
}@args:

stdenvNoCC.mkDerivation (
  {
    inherit pname version src;

    nativeBuildInputs = [ unzip ];

    dontUnpack = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      if [ -d "$src" ]; then
        source_root="$src"
      else
        mkdir unpacked
        unzip "$src" -d unpacked
        source_root="unpacked"
      fi

      # Some plugin archives wrap files in a single top-level directory.
      shopt -s nullglob dotglob
      entries=("$source_root"/*)

      mkdir -p "$out/lib/jellyfin/plugins/${pname}"

      if [ "''${#entries[@]}" -eq 1 ] && [ -d "''${entries[0]}" ]; then
        cp -a "''${entries[0]}"/. "$out/lib/jellyfin/plugins/${pname}/"
      else
        cp -a "$source_root"/. "$out/lib/jellyfin/plugins/${pname}/"
      fi

      runHook postInstall
    '';

    meta = {
      platforms = lib.platforms.all;
    } // meta;
  }
  // removeAttrs args [
    "pname"
    "version"
    "src"
    "meta"
  ]
)
