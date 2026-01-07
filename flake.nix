{
  description = "Jotup - A parser for the Djot markup language";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    flakebox.url = "github:rustshop/flakebox?rev=9a22c690bc3c15291c3c70f662c855b5bdaffc0e";

    bundlers = {
      url = "github:NixOS/bundlers";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Keep rust-overlay for fuzz shell
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      flakebox,
      bundlers,
      rust-overlay,
    }:
    {
      bundlers = bundlers.bundlers;
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        projectName = "jotup";

        flakeboxLib = flakebox.lib.mkLib pkgs {
          config = {
            just.importPaths = [ "justfile.jotup.just" ];
            toolchain.channel = "latest";
            rust.rustfmt.enable = false;
            linker.wild.enable = true;
          };
        };

        stdToolchains = (flakeboxLib.mkStdToolchains { });

        toolchainAll = (
          flakeboxLib.mkFenixToolchain {
            targets = pkgs.lib.getAttrs [ "default" ] (flakeboxLib.mkStdTargets { });
          }
        );

        # Nightly toolchain for fuzzing (cargo-fuzz requires nightly)
        toolchainNightly = flakeboxLib.mkFenixToolchain {
          channel = "nightly";
          targets = pkgs.lib.getAttrs [ "default" ] (flakeboxLib.mkStdTargets { });
        };

        buildPaths = [
          "Cargo.toml"
          "Cargo.lock"
          "src"
          "examples"
          "tests"
          "bench"
          ".*\\.rs"
        ];

        buildSrc = flakeboxLib.filterSubPaths {
          root = builtins.path {
            name = projectName;
            path = ./.;
          };
          paths = buildPaths;
        };

        # Source filter for fuzz targets (includes corpus)
        fuzzSrc = flakeboxLib.filterSubPaths {
          root = builtins.path {
            name = "${projectName}-fuzz";
            path = ./.;
          };
          paths = [
            "Cargo.toml"
            "Cargo.lock"
            "src"
            "fuzz"
            "fuzz/.*"
            ".*\\.rs"
          ];
        };

        multiBuild =
          (flakeboxLib.craneMultiBuild {
            toolchains = stdToolchains;
          })
            (
              craneLib':
              let
                craneLib = (
                  craneLib'.overrideArgs {
                    pname = projectName;
                    src = buildSrc;
                    nativeBuildInputs = [ ];
                  }
                );
              in
              rec {
                workspaceDeps = craneLib.buildWorkspaceDepsOnly { };

                workspace = craneLib.buildWorkspace {
                  cargoArtifacts = workspaceDeps;
                };

                jotup = craneLib.buildPackage {
                  cargoArtifacts = workspace;
                  meta.mainProgram = "jotup";
                };

                tests = craneLib.cargoNextest {
                  cargoArtifacts = workspace;
                };

                clippy = craneLib.cargoClippy {
                  # must be deps, otherwise it will not rebuild
                  # anything and thus not detect anything
                  cargoArtifacts = workspaceDeps;
                };

                # Fuzz target builder function
                mkFuzzTarget =
                  {
                    target,
                    fuzzArgs ? "-max_total_time=10 -seed=1",
                  }:
                  let
                    # Use rust-overlay nightly directly
                    rustNightly = pkgs.rust-bin.nightly.latest.default.override {
                      extensions = [
                        "rust-src"
                        "llvm-tools-preview"
                      ];
                    };
                  in
                  pkgs.stdenv.mkDerivation {
                    pname = "${projectName}-fuzz-${target}";
                    version = "0.9.0";
                    src = fuzzSrc;

                    cargoDeps = pkgs.rustPlatform.importCargoLock {
                      lockFile = ./fuzz/Cargo.lock;
                    };

                    # cargoSetupHook expects this
                    cargoRoot = "fuzz";

                    nativeBuildInputs = with pkgs; [
                      rustNightly
                      cargo-fuzz
                      rustPlatform.cargoSetupHook
                    ];

                    buildPhase = ''
                      export CARGO_HOME=$(mktemp -d cargo-home.XXX)
                      echo "Building fuzz target: ${target}"
                      cargo build --manifest-path fuzz/Cargo.toml --bin ${target} --release
                    '';

                    # Run the fuzz target as a check
                    doCheck = true;
                    checkPhase = ''
                      echo "Running fuzz target: ${target}"
                      echo "Args: ${fuzzArgs}"

                      # Run with cargo-fuzz
                      cargo fuzz run ${target} -- ${fuzzArgs}
                    '';

                    # Create a marker file to indicate success
                    installPhase = ''
                      mkdir -p $out
                      echo "Fuzz target ${target} completed successfully with args: ${fuzzArgs}" > $out/SUCCESS
                      echo "cargo fuzz run ${target} -- ${fuzzArgs}" > $out/command
                    '';
                  };

                # Fuzz target derivations with default 10s runs
                fuzzParse = mkFuzzTarget { target = "parse"; };
                fuzzHtml = mkFuzzTarget { target = "html"; };
                fuzzCompareRenderers = mkFuzzTarget { target = "compare_renderers"; };
              }
            );
        jotup = multiBuild.jotup;
      in
      {
        packages = {
          inherit jotup;
          default = jotup;
        };

        legacyPackages = multiBuild;

        devShells = {
          default =
            (flakeboxLib.mkShells {
              toolchain = toolchainAll;
              packages = [ ];
            }).default;

          # Keep existing fuzz shell
          fuzz = pkgs.mkShell {
            buildInputs = [
              (pkgs.rust-bin.nightly.latest.default.override {
                extensions = [
                  "rust-src"
                  "llvm-tools-preview"
                ];
              })
              pkgs.cargo-fuzz
            ];
          };
        };
      }
    );
}
