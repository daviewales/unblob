{ lib
, makeWrapper
, mkPoetryApp
, poetry2nix
, glibc
, python3
, rustPlatform
, e2fsprogs
, lz4
, lziprecover
, lzo
, lzop
, p7zip
, sasquatch
, simg2img
, unar
, file
}:

let
  # These dependencies are only added to PATH
  runtimeDeps = [
    e2fsprogs
    lz4
    lziprecover
    lzop
    p7zip
    sasquatch
    sasquatch.bigEndian
    simg2img
    unar
  ];

  self = mkPoetryApp {
    projectDir = ./.;

    # Python dependencies that need special care, like non-python
    # build dependencies
    overrides = poetry2nix.overrides.withDefaults (self: super: {
      python-lzo = super.python-lzo.overridePythonAttrs (_: {
        buildInputs = [
          lzo
        ];
      });

      jefferson = super.jefferson.overridePythonAttrs (_: {
        propagatedBuildInputs = [
          # Use the _same_ version as unblob
          self.cstruct
          self.python-lzo
        ];
      });

      ubi_reader = super.ubi_reader.ovveridePythonAttrs (_: {
        propagatedBuildInputs = [
          # Use the _same_ version as unblob
          self.python-lzo
        ];
      });

      file-magic = super.file-magic.overridePythonAttrs (_: {
        patchPhase = ''
          substituteInPlace magic.py --replace "find_library('magic')" "'${file}/lib/libmagic.so'"
        '';
      });
    });

    python = python3;

    postFixup = ''
      wrapProgram $out/bin/unblob --prefix PATH : ${lib.makeBinPath runtimeDeps} \
                                  --set LOCALE_ARCHIVE_2_27 ${glibc}/lib/locale/locale-archive \
                                  --set LC_ALL C.UTF-8
    '';

    UNBLOB_BUILD_RUST_EXTENSION = "1";

    cargoDeps = rustPlatform.importCargoLock {
      lockFile = ./Cargo.lock;
    };

    nativeBuildInputs = with rustPlatform; [
      cargoSetupHook
      makeWrapper
      rust.cargo
      rust.rustc
    ];

    editablePackageSources = { "unblob" = ./unblob; };
  };
in
self // {
  inherit runtimeDeps;
  withTests = self.app.overridePythonAttrs (_: {
    checkPhase = ''
      (
        deps_PATH=${lib.makeBinPath runtimeDeps}

        # $program_PATH is set to contain all the script-paths of all
        # Python dependencies
        export PATH=$deps_PATH:$program_PATH:$PATH

        # romfs sample file contains some funky symlinks which get
        # removed when source is copyed to the nix store.
        pytest -k "not test_all_handlers[filesystem.romfs]" --no-cov
      )
    '';
  });
}
