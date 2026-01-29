{
  lib,
  rustPlatform,
  fetchFromGitHub,
  nix-update-script,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "nu_plugin_nupsql";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "HertelP";
    repo = "nu_plugin_nupsql";
    rev = "c664f6b38128c746e3be7aa964e1656c04d8257d";
    hash = "sha256-JO977MEQIEb5+YEGD9gPNpdyQfBUh8KQ0TipsZ90KJY=";
  };

  cargoHash = "sha256-609w/7vmKcNv1zSfd+k6TTeU2lQuzHX3W5Y8EqKIiAM=";

  passthru.update-script = nix-update-script { };

  meta = {
    description = "A nushell plugin to query postgres databases.";
    homepage = "https://gitlab.com/HertelP/nu_plugin_nupsql";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ philocalyst ];
    mainProgram = "nu_plugin_nupsql";
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };
})
