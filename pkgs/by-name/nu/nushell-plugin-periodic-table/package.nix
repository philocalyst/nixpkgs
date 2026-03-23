{
  stdenv,
  lib,
  rustPlatform,
  fetchFromGitHub,
  nix-update-script,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "nu_plugin_periodic_table";
  version = "0.2.12";
  src = fetchFromGitHub {
    owner = "JosephTLyons";
    repo = "nu_plugin_periodic_table";
    rev = "v${finalAttrs.version}";
    hash = "sha256-/trR4OofJq26sgi9HtMZHxeO05MEIDCjYTTtbrdDkNM=";
  };

  cargoHash = "sha256-u8w8WFfmzSTEwm+AamMwngbHsuFk4lut/FcV+VKYcKo=";

  nativeBuildInputs = lib.optionals stdenv.cc.isClang [ rustPlatform.bindgenHook ];

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "A periodic table of elements plugin for Nushell";
    mainProgram = "nu_plugin_periodic_table";
    homepage = "https://github.com/JosephTLyons/nu_plugin_periodic_table";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [ philocalyst ];
  };
})
