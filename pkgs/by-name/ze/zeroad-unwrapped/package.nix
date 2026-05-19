{
  stdenv,
  lib,
  perl,
  python3,
  fmt_9,
  libidn,
  pkg-config,
  spidermonkey_140,
  boost,
  icu,
  libxml2,
  libpng,
  libsodium,
  libjpeg,
  zlib,
  curl,
  libogg,
  libvorbis,
  enet,
  miniupnpc,
  openal,
  libGLU,
  libGL,
  xorgproto,
  libx11,
  fetchgit,
  fetchsvn,
  libxcursor,
  nspr,
  SDL2,
  gloox,
  nvidia-texture-tools,
  premake5,
  cxxtest,
  freetype,
  wxwidgets_3_2,

  withLobby ? true,

  withEditor ? true,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "0ad";
  version = "0.28.0";

  __structuredAttrs = true;
  strictDeps = true;

  # fetchFromGitea/fetchurl fails because the Wildfire Games Gitea instance
  # has bot protection (Anubis).
  src = fetchgit {
    url = "https://gitea.wildfiregames.com/0ad/0ad.git";
    rev = "v${finalAttrs.version}";
    hash = "sha256-RDQ1Av8XBHFU0q9bVkjRvTqg+zVGunq6LfMAP12Lh7A=";
  };

  passthru = {
    fcollada = fetchsvn {
      url = "https://svn.wildfiregames.com/public/source-libs/trunk/fcollada";
      rev = 28209;
      hash = "sha256-gfbIukYILTF+GA64QlPHfKhxb9bIffiunj07f0RC7oY=";
    };
  };

  nativeBuildInputs = [
    python3
    perl
    pkg-config
    premake5
    libxml2.dev
  ];

  buildInputs = [
    spidermonkey_140
    boost
    icu
    libxml2
    libpng
    libjpeg
    zlib
    curl
    libogg
    libvorbis
    enet
    miniupnpc
    openal
    libidn
    nspr
    SDL2
    gloox
    nvidia-texture-tools
    libsodium
    fmt_9
    freetype
    cxxtest
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    libGLU
    libGL
    xorgproto
    libx11
    libxcursor
  ]
  ++ lib.optional withEditor wxwidgets_3_2;

  env = {
    MIN_OSX_VERSION = stdenv.hostPlatform.darwinMinVersion or "";
    ${if stdenv.isLinux then "NIX_CFLAGS_LINK" else "NIX_LDFLAGS"} =
      "-L${nvidia-texture-tools.lib}/lib${lib.optionalString stdenv.isLinux "/static"}";
  }
  // lib.optionalAttrs withEditor {
    WX_CONFIG = "${lib.getBin wxwidgets_3_2}/bin/wx-config";
  };

  patches = [
    ./rootdir_env.patch
    ./use-mozjs-140.patch
    ./adapt-js-api-to-esr-140.patch
  ];

  makeFlags = [
    "config=release"
    "verbose=1"
  ];

  configurePhase = ''
    runHook preConfigure

    rm -rf libraries/source/{cxxtest-4.4,nvtt,premake-core,spidermonkey,spirv-reflect}
    # Remove bundled macOS iconv — Nix provides system libiconv and the bundled
    # headers conflict with the system ones from propagated build inputs.
    rm -rf libraries/macos/iconv

    # Fix ambiguous iconv calls in tinygettext when both <iconv.h> (system)
    # and tinygettext/iconv.hpp (inline wrappers) are visible in the same TU.
    substituteInPlace source/third_party/tinygettext/src/iconv.cpp \
      --replace-fail '    iconv_close(cd);' '    ::iconv_close(cd);'
    substituteInPlace source/third_party/tinygettext/src/iconv.cpp \
      --replace-fail '        iconv(cd, nullptr, nullptr, nullptr, nullptr);' \
      '        ::iconv(cd, nullptr, nullptr, nullptr, nullptr);'

    pushd libraries
      # build-source-libs.sh refuses to run on macOS; neutralise the guard
      # since we use --with-system-* and Nix provides all dependencies.
      substituteInPlace build-source-libs.sh \
        --replace-fail 'die "This script should not be used on macOS: use build-macos-libs.sh instead."' \
                  'echo "Nix build on macOS, continuing..."'

      # Pre-populate fcollada source via fetchsvn to avoid runtime svn
      mkdir -p source/fcollada/fcollada-28209
      cp -R ${finalAttrs.passthru.fcollada}/* source/fcollada/fcollada-28209/
      # Nix store files are read-only; make writable so rm -Rf succeeds
      chmod -R u+w source/fcollada/fcollada-28209
      tar cJf source/fcollada/fcollada-28209.tar.xz \
        -C source/fcollada fcollada-28209
      rm -Rf source/fcollada/fcollada-28209

      ./build-source-libs.sh \
        --with-system-cxxtest \
        --with-system-nvtt \
        --with-system-mozjs \
        --with-system-premake \
        -j$NIX_BUILD_CORES
    popd

    pushd build/workspaces
      ./update-workspaces.sh \
        --with-system-premake5 \
        --with-system-cxxtest \
        --with-system-nvtt \
        --with-system-mozjs \
        ${lib.optionalString (!withEditor) "--without-atlas"} \
        ${lib.optionalString (!withLobby) "--without-lobby"} \
        --without-pch \
        --bindir="$out"/bin \
        --libdir="$out"/lib/0ad \
        --datadir="$out/share/0ad" \
        --without-tests \
        -j $NIX_BUILD_CORES
    popd

    pushd build/workspaces/gcc
      runHook postConfigure
    popd
  '';

  enableParallelBuilding = true;

  installPhase = ''
    install -Dm755 binaries/system/pyrogenesis "$out"/bin/0ad
    ${lib.optionalString withEditor ''
      install -Dm755 binaries/system/ActorEditor "$out"/bin/ActorEditor
    ''}

    install -Dm755 -t $out/share/0ad/data/l10n binaries/data/l10n/*

    mkdir -p "$out/lib/0ad"

    shopt -s nullglob
    for f in binaries/system/*.so binaries/system/*.dylib; do
      [[ -e "$f" ]] || continue
      install -Dm644 "$f" "$out/lib/0ad/$(basename "$f")"
    done

    install -D build/resources/0ad.png $out/share/icons/hicolor/128x128/apps/0ad.png
    install -D build/resources/0ad.desktop $out/share/applications/0ad.desktop
  '';

  meta = {
    changelog = "https://play0ad.com/new-release-0-a-d-release-28-boiorix/";
    # Free, open-source game of ancient warfare
    description = "0 A.D. — ancient warfare real-time strategy game";
    homepage = "https://play0ad.com/";
    license = with lib.licenses; [
      gpl2Plus
      lgpl21
      mit
      cc-by-sa-30
      lib.licenses.zlib # otherwise masked by pkgs.zlib
    ];
    maintainers = with lib.maintainers; [
      chvp
      philocalyst
    ];
    platforms = (lib.subtractLists lib.platforms.i686 lib.platforms.linux) ++ lib.platforms.darwin;
    mainProgram = "0ad";
    longDescription = ''
      0 A.D. (pronounced "zero-ey-dee") is a free, open-source, cross-platform real-time strategy
      game of ancient warfare. It is a historical-warfare and economy game, similar in spirit to the
      Age of Empires series, with the player guiding the development of a civilization from a small
      settlement to an empire.
    '';
  };
})
