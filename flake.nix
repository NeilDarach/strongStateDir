{
  description = "Simple interface to create ZFS state dirs for services";
  inputs = { nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05"; };

  outputs = inputs@{ nixpkgs, ... }: {

    nixosModules.default = { config, inputs, pkgs, lib, ... }: {
      options = let
        strongStateDetails = lib.types.submodule ({ name, ... }: {
          options = {
            enabled = lib.mkEnableOption "If the state dir is enabled";
            serviceName = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Base name for all the config elements";
            };

          };
        });
      in {
        strongStateDir = lib.mkOption {
          type = lib.types.attrsOf strongStateDetails;
          default = { };
        };
      };
      config = let
        enabledServices =
          lib.filter (ea: ea.enabled) (lib.attrValues config.strongStateDir);
        mkStrongStateDirSrc = builtins.readFile ./strongStateDir;
        mkStrongStateDir = (pkgs.writeScriptBin "mkStrongStateDir"
          mkStrongStateDirSrc).overrideAttrs (p: {
            buildCommand = ''
              ${p.buildCommand}
              patchShebangs $out
            '';
          });
        wrappedMkStrongStateDir = pkgs.symlinkJoin {
          name = "mkStrongStateDir";
          paths = [ mkStrongStateDir ]
            ++ (with pkgs; [ gzip openssh gnugrep util-linux ]);
          buildInputs = [ pkgs.makeWrapper ];
          postBuild =
            "wrapProgram $out/bin/mkStrongStateDir --prefix PATH : $out/bin";
        };
      in {
        environment.etc.strongStateDir = {
          text = "${wrappedMkStrongStateDir}/bin/mkStrongStateDir "
            + (lib.concatStringsSep " "
              (map (ea: lib.escapeShellArg ea.serviceName) enabledServices));
        };
      };
    };
  };
}
