{
  stdenv,
  lib,
  rustPlatform,
  nix-update-script,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "nu_plugin_dns";
  version = "4.0.7";

  src = fetchFromGitHub {
    owner = "dead10ck";
    repo = "nu_plugin_dns";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Kadka38te8F0GFbnni3Oc6cdxHAS+yGtukZdPxbkmIA=";
  };

  cargoHash = "sha256-u8C+yvcsEwEwbubgIITtkjpvL/TluYVtPV4skH0dY8E=";

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Nushell plugin that does DNS queries and parses results into meaningful types.";
    mainProgram = "nu_plugin_dns";
    homepage = "https://github.com/dead10ck/nu_plugin_dns";
    license = lib.licenses.mpl20;
    maintainers = with lib.maintainers; [ philocalyst ];
  };
})
