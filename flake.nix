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
      in {
        environment.etc.strongStateDir = {
          text =
            lib.concatStringsSep "|" (map (ea: ea.serviceName) enabledServices);
        };
      };
    };
  };
}
