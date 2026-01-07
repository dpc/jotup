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
