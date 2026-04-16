{
  lib,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  cmake,
  bun,
  nodejs,
  cctools,
  cargo-tauri,
  jq,
  writableTmpDirAsHomeHook,
  makeBinaryWrapper,
  swift,

  # Linux-only
  webkitgtk_4_1,
  gtk3,
  glib,
  libsoup_3,
  alsa-lib,
  libayatana-appindicator,
  libevdev,
  libxtst,
  gtk-layer-shell,
  vulkan-loader,
  vulkan-headers,
  shaderc,
  gst_all_1,
  glib-networking,
  libx11,
  pipewire,
  alsa-plugins,
  symlinkJoin,
  wrapGAppsHook4,

  # Cross-platform
  onnxruntime,
  openssl,
}:

rustPlatform.buildRustPackage (
  finalAttrs:
  let
    gstPlugins = lib.optionals stdenv.hostPlatform.isLinux (
      with gst_all_1;
      [
        gstreamer
        gst-plugins-base
        gst-plugins-good
        gst-plugins-bad
        gst-plugins-ugly
      ]
    );

    # Per-platform bun node_modules hashes; --production is intentionally
    # omitted because devDeps (e.g. @types/*) are required for tsc at
    # build time. Bun downloads host-matching native binaries only, so
    # each system has a distinct hash.
    # Details: https://github.com/cjpais/Handy/pull/1256
    # TODO: switch to bun.fetchDeps once NixOS/nixpkgs#376299 is merged.
    frontendDepsHashes = {
      "x86_64-linux" = "sha256-tJ6LK99dELOiR0BcsTRTt/vLyNamntujLxhBy5Xl/lc=";
      "aarch64-linux" = "sha256-S+dX6ZVgv9dexxIHoa5PxP7e0nxf/d7cKUGty5eEi8A=";
      "aarch64-darwin" = "sha256-DQbogNBQ9izK5GPmoOudqiB2lJvct1vZI2U5lp3WFy8=";
    };
    frontendDeps = stdenv.mkDerivation {
      pname = "${finalAttrs.pname}-frontend-deps";
      inherit (finalAttrs) version src;
      nativeBuildInputs = [
        bun
        writableTmpDirAsHomeHook
      ];
      dontConfigure = true;
      buildPhase = ''
        runHook preBuild
        export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
        bun install --linker=isolated --force --frozen-lockfile \
          --ignore-scripts --no-progress
        bun --bun "$PWD/.nix/scripts/normalize-install.ts"
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p $out
        cp -R node_modules $out/
        runHook postInstall
      '';
      dontFixup = true;
      outputHash =
        frontendDepsHashes.${stdenv.hostPlatform.system} or (throw ''
          handy: no frontendDeps hash for ${stdenv.hostPlatform.system}.
          Run `nix-update --flake handy` (or the equivalent `passthru.updateScript`)
          on a host of that system and paste the value into
          pkgs/by-name/ha/handy/package.nix:frontendDepsHashes.
        '');
      outputHashMode = "recursive";
    };
  in
  {
    pname = "handy";
    version = "0.8.2";

    __structuredAttrs = true;

    # TEMPORARY: pin to cjpais/Handy#1256 for .nix/scripts/normalize-install.ts.
    # Revert to tag = "v${finalAttrs.version}" after #1256 merges and is released.
    src = fetchFromGitHub {
      owner = "cjpais";
      repo = "Handy";
      rev = "681c6a991b7e55bd04ef9963aeb45767ebacba2e";
      hash = "sha256-9SfVRef31Ak4H4yEUmw0R8ySqWV9F98LUhSCH+rGw/I=";
    };

    cargoRoot = "src-tauri";
    cargoHash = "sha256-qwcKuPfSLVmjIkduKkIRCmVk6BPbxF5htfY6f+6yV0w=";

    postPatch = ''
      # Strip updater artifacts; disable macOS code-signing in sandbox
      ${jq}/bin/jq '
        del(.build.beforeBuildCommand) |
        .bundle.createUpdaterArtifacts = false |
        .bundle.macOS.signingIdentity = null |
        .bundle.macOS.hardenedRuntime = false
      ' src-tauri/tauri.conf.json > $TMPDIR/tauri.conf.json
      cp $TMPDIR/tauri.conf.json src-tauri/tauri.conf.json

      ${jq}/bin/jq 'del(.scripts.postinstall)' package.json > $TMPDIR/package.json
      cp $TMPDIR/package.json package.json

      # cbindgen's cargo metadata fails in the sandbox
      find $cargoDepsCopy -path "*/ferrous-opencc-*/build.rs" \
        -exec sed -i \
          -e '/cbindgen::Builder::new/{:l;/write_to_file/!{N;bl};d}' \
          {} \;
    ''
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      find $cargoDepsCopy -path "*/libappindicator-sys-*/src/lib.rs" \
        -exec sed -i \
          's|libayatana-appindicator3.so.1|${libayatana-appindicator}/lib/libayatana-appindicator3.so.1|' \
          {} \;
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      patch -p1 < ${./use-nix-swift.patch}
    '';

    nativeBuildInputs = [
      pkg-config
      cmake
      bun
      nodejs
      cargo-tauri.hook
      jq
      rustPlatform.bindgenHook
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      wrapGAppsHook4
      shaderc
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      makeBinaryWrapper
      cctools
      swift
    ];

    buildInputs = [
      onnxruntime
      openssl
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      webkitgtk_4_1
      gtk3
      glib
      libsoup_3
      alsa-lib
      libayatana-appindicator
      libevdev
      libxtst
      gtk-layer-shell
      vulkan-loader
      vulkan-headers
      glib-networking
      libx11
    ]
    ++ gstPlugins;

    env = {
      ORT_LIB_LOCATION = "${onnxruntime}/lib";
      ORT_PREFER_DYNAMIC_LINK = "1";
      GST_PLUGIN_SYSTEM_PATH_1_0 = lib.optionalString stdenv.hostPlatform.isLinux (
        lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" gstPlugins
      );
      OPENSSL_NO_VENDOR = "1";
    }
    // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
      SWIFTC = "${swift}/bin/swiftc";
    };

    preBuild = ''
      cp -R ${frontendDeps}/node_modules .
      chmod -R u+w node_modules
      patchShebangs node_modules
      export HOME=$TMPDIR
      bun run build
    '';

    doCheck = false;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
    ''
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      mv src-tauri/target/${stdenv.hostPlatform.rust.rustcTarget}/release/bundle/deb/*/data/usr/* $out/
    ''
    + lib.optionalString stdenv.hostPlatform.isDarwin ''
      mkdir -p $out/Applications $out/bin
      mv src-tauri/target/${stdenv.hostPlatform.rust.rustcTarget}/release/bundle/macos/Handy.app \
        $out/Applications/
      makeWrapper "$out/Applications/Handy.app/Contents/MacOS/handy" "$out/bin/handy"
    ''
    + ''
      runHook postInstall
    '';

    preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
      gappsWrapperArgs+=(
        --set WEBKIT_DISABLE_DMABUF_RENDERER 1
        --set ALSA_PLUGIN_DIR "${
          symlinkJoin {
            name = "combined-alsa-plugins";
            paths = [
              "${pipewire}/lib/alsa-lib"
              "${alsa-plugins}/lib/alsa-lib"
            ];
          }
        }"
        --prefix LD_LIBRARY_PATH : "${
          lib.makeLibraryPath [
            vulkan-loader
            onnxruntime
          ]
        }"
      )
    '';

    # onnxruntime rpath (DYLD_LIBRARY_PATH is blocked by SIP on macOS)
    postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
      install_name_tool -add_rpath ${onnxruntime}/lib \
        "$out/Applications/Handy.app/Contents/MacOS/handy"
    '';

    passthru = {
      inherit frontendDeps;
      # nix-update-script cannot manage per-platform frontendDepsHashes;
      # this wraps nix-update and refreshes the current host's entry.
      updateScript = ./update.sh;
    };

    meta = {
      description = "Free, open source, offline speech-to-text application";
      longDescription = ''
        Handy is a cross-platform desktop application providing simple,
        privacy-focused speech transcription. Press a shortcut, speak, and
        have your words appear in any text field — entirely on your own
        computer, with no audio sent to the cloud.
      '';
      homepage = "https://handy.computer";
      changelog = "https://github.com/cjpais/Handy/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.mit;
      mainProgram = "handy";
      maintainers = with lib.maintainers; [ philocalyst ];
      platforms = lib.platforms.linux ++ lib.platforms.darwin;
    };
  }
)
