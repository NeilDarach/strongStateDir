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
            dirName = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Name of the dataset and mount point";
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
            ++ (with pkgs; [ gzip openssh gnugrep util-linux zfs ]);
          buildInputs = [ pkgs.makeWrapper ];
          postBuild =
            "wrapProgram $out/bin/mkStrongStateDir --prefix PATH : $out/bin";
        };
        zfsBackupSrc = builtins.readFile ./zfs-backup;
        zfsBackup =
          (pkgs.writeScriptBin "zfs-backup" zfsBackupSrc).overrideAttrs (p: {
            buildCommand = ''
              ${p.buildCommand}
              patchShebangs $out
            '';
          });
        wrappedZfsBackup = pkgs.symlinkJoin {
          name = "zfs-backup";
          paths = [ zfsBackup ] ++ (with pkgs; [ gzip openssh coreutils zfs ]);
          buildInputs = [ pkgs.makeWrapper ];
          postBuild =
            "wrapProgram $out/bin/zfs-backup --prefix PATH : $out/bin";
        };
      in {
        systemd.services = {
          "zfs-backup@" = lib.mkIf (lib.len enabledServices > 0) {
            description = "Backup a strong state dir";
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              ExecStart = "${wrappedZfsBackup}/bin/zfs-backup %i";
            };
          };
          "strongStateDir@" = lib.mkIf (lib.len enabledServices > 0) {
            description = "Set up the state dir";
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              ExecStart = "${wrappedMkStrongStateDir}/bin/mkStrongStateDir %i";
            };
          };
        } // lib.mapAttrs (ea:
          let
            user = config.systemd.services.${ea.serviceName}.serviceConfig.User;
            group =
              config.systemd.services.${ea.serviceName}.serviceConfig.Group;
          in {
            "${ea.serviceName}".serviceConfig.wants = [
              "strongStateDir@${ea.dirName}:${user}:${group}:${ea.serviceName}.service"
            ];
          }) enabledServices;

        systemd.timers = lib.mapAttrs (ea: {
          "strongStateDir-backup-${ea.serviceName}" = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "Sun 20:03:00";
              RandomizedDelaySec = "1200";
              Unit = "zfs-backup@${ea.dirName}:${ea.serviceName}";
            };
          };
        }) enabledServices;
      };
    };
  };
}
