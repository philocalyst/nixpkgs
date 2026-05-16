{
  stdenv,
  hurrycurry-server,
  godot,
  ffmpeg,
  writableTmpDirAsHomeHook,
  copyDesktopItems,
  makeDesktopItem,
  unzip,
  lib,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "hurrycurry-client";
  inherit (hurrycurry-server) version src;

  nativeBuildInputs = [
    godot
    ffmpeg
    writableTmpDirAsHomeHook
    makeWrapper
  ]
  ++ lib.optionals stdenv.isLinux [ copyDesktopItems ]
  ++ lib.optionals stdenv.isDarwin [ unzip ];

  postPatch = ''
    patchShebangs --build data/recipes/anticurry.sed
  '';

  buildPhase = ''
    runHook preBuild

    ${
      if stdenv.isDarwin then
        ''
          mkdir -p "$HOME/Library/Application Support/Godot/export_templates"
          ln -s "${godot.export-template}/share/godot/export_templates/4.6.2.stable" \
            "$HOME/Library/Application Support/Godot/export_templates/4.6.2.stable"
        ''
      else
        ''
          ln -s "${godot.export-template}" "$HOME/.local"
        ''
    }

    make all_client

    pushd client
      mkdir -p build

      godot --headless --export-release "${
        if stdenv.isDarwin then "all-apple-darwin" else stdenv.hostPlatform.config
      }" ./build/hurrycurry${lib.optionalString stdenv.isDarwin ".zip"}
    popd

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    ${lib.optionalString stdenv.isDarwin ''
      mkdir -p "$out/Applications" "$out/bin"
      unzip client/build/hurrycurry.zip -d "$out/Applications"

      # No binary output on Darwin due to lack of a way to resolve .pck searching
    ''}

    ${lib.optionalString (!stdenv.isDarwin) ''
      install -Dm755 client/build/hurrycurry -t $out/bin
      install -Dm644 client/icons/main.png \
        $out/share/icons/hicolor/1024x1024/apps/hurrycurry.png
    ''}

    runHook postInstall
  '';

  desktopItems = lib.optionals stdenv.isLinux [
    (makeDesktopItem {
      type = "Application";
      name = "hurrycurry";
      exec = "hurrycurry";
      icon = "hurrycurry";
      terminal = false;
      comment = "Cooperative 3D multiplayer game about cooking";
      desktopName = "Hurry Curry!";
      categories = [ "Game" ];
    })
  ];

  meta = hurrycurry-server.meta // {
    mainProgram = "hurrycurry";
  };
}
