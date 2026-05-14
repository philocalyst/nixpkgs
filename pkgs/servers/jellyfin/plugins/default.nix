{
  lib,
  callPackage,
  fetchzip,
}:

let
  buildJellyfinPlugin = callPackage ./buildJellyfinPlugin.nix { };

  pluginData = lib.importJSON ./generated.json;

  plugins = lib.mapAttrs' (
    name: info:
    lib.nameValuePair info.pname (buildJellyfinPlugin {
      pname = info.pname;
      version = info.version;
      src = fetchzip {
        url = info.url;
        hash = info.hash;
        # For plugins that just contain the DLL at the root level, fetchzip would fail if stripRoot is true
        stripRoot = false;
      };
      meta = {
        description = info.description;
        homepage = "https://jellyfin.org/";
        maintainers = with lib.maintainers; [ ];
      };
    })
  ) pluginData;
in
plugins // {
  inherit buildJellyfinPlugin;
}
