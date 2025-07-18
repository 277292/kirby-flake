{
  description = "Kirby CMS Flake";

  outputs = {
    self,
    nixpkgs,
    ...
  }: {
    overlays.kirby = final: _prev: let
      inherit (final) fetch fetchFromGitHub php83 php84;
      inherit (final.stdenv) mkDerivation;
    in {
      fetch = {
        version,
        rev,
        sha256,
        phpPackage,
      }:
        mkDerivation {
          pname = "kirby";
          inherit version;
          src = fetchFromGitHub {
            owner = "getkirby";
            repo = "kirby";
            inherit rev sha256;
          };

          installPhase = ''
            mkdir -p $out
            cp -r . $out
          '';

          meta = {
            description = "Kirby: the CMS that adapts to any project, loved by developers and editors alike.";
            homepage = "https://github.com/getkirby/kirby";
            license = {
              free = false;
              redistributable = false;
              fullName = "While Kirby's source code is publicly available, Kirby is not free. To use Kirby in production, you need to purchase a license.";
              url = "https://getkirby.com/license";
            };
          };

          passthru = {inherit phpPackage;};
        };

      # nix run nixpkgs#nix-prefetch-github -- getKirby kirby --rev <version>
      kirby3 = fetch {
        version = "3.10.1.2";
        rev = "dba5ea8ea7fd468190a401cc37d6032ec717cac8";
        sha256 = "sha256-sEPSquK1m3VtN3H1LJ53UY3CO9RLDv9GhYPTRSNSCEE=";
        phpPacakge = php83;
      };

      kirby4 = fetch {
        version = "4.8.0";
        rev = "5292c17832dd34b0e5f3e98dea837a357ef037b6";
        sha256 = "sha256-eIkuXpNS0sB29IqGM/L2OTrTRhciSBnDudfn9960Pzs=";
        phpPackage = php84;
      };

      kirby5 = fetch {
        version = "5.0.2";
        rev = "a57580ac93c643e2e4f84a804bb37b511d445349";
        sha256 = "sha256-21wfqbfj7Qkl8bmwqf+lVNQPZM0AC5R4XIitbrCUoOA=";
        phpPackage = php84;
      };
    };

    nixosModules.kirby = {
      config,
      lib,
      pkgs,
      ...
    }: let
      inherit (lib) mkOption mkIf mapAttrs mapAttrs' filterAttrs;
      inherit (lib.types) submodule attrsOf listOf nullOr bool str path package;

      cfg = config.kirby-cms;
    in {
      options.kirby-cms = {
        default = {
          root = mkOption {
            type = path;
            default = "/var/www";
            description = "Default root directory for all Kirby instances. Can be overridden per instance.";
          };
          timezone = mkOption {
            type = str;
            default = "UTC";
            description = "Sets the PHP-FPM date.timezone setting for all instances. Can be overridden per instance.";
          };
          package = mkOption {
            type = nullOr package;
            default = null;
            description = "Default Kirby package used by all instances. Can be overridden per instance.";
            example = "pkgs.kirby4";
          };
        };
        sites = mkOption {
          type = attrsOf (submodule ({name, ...}: {
            options = {
              enable = mkOption {
                type = bool;
                default = true;
                description = "Whether to enable this Kirby instance.";
              };
              hostName = mkOption {
                type = str;
                default = name;
                description = "Hostname for the instance. Defaults to the instance name. A 'www.' alias is automatically added.";
                example = "getkirby.com";
              };
              serverAliases = mkOption {
                type = listOf str;
                default = [];
                description = "List of additional domain names. A 'www.' alias is automatically added for each entry.";
              };
              root = mkOption {
                type = path;
                default = "${cfg.default.root}/${name}";
                description = "Root directory for this Kirby instance.";
              };
              timezone = mkOption {
                type = str;
                default = cfg.default.timezone;
                description = "PHP-FPM date.timezone setting for this instance.";
              };
              package = mkOption {
                type = package;
                default = cfg.default.package;
                description = "Kirby package used by this instance.";
                example = "pkgs.kirby4";
              };
            };
          }));
        };
      };

      config = {
        users.users = mapAttrs (name: {
          enable,
          hostName,
          root,
          ...
        }:
          mkIf enable {
            description = "Kirby Instance for ${hostName}";
            isSystemUser = true;
            createHome = true;
            homeMode = "2775";
            home = root;
            group = name;
          })
        cfg.sites;

        users.groups = mapAttrs (_name: {enable, ...}: mkIf enable {members = ["nginx"];}) cfg.sites;

        services.phpfpm.pools = mapAttrs (name: {
          enable,
          timezone,
          package,
          ...
        }:
          mkIf enable {
            user = name;
            phpPackage = package.phpPackage;
            settings = {
              "listen.owner" = config.services.nginx.user;
              "pm" = "dynamic";
              "pm.max_children" = 5;
              "pm.start_servers" = 2;
              "pm.min_spare_servers" = 1;
              "pm.max_spare_servers" = 3;
              "pm.max_requests" = 500;
              "php_admin_value[error_log]" = "stderr";
              "php_admin_flag[log_errors]" = true;
              "catch_workers_output" = true;
            };
            phpOptions = ''
              date.timezone = ${timezone};
              cgi.fix_pathinfo = 1
            '';
          })
        cfg.sites;

        services.nginx.virtualHosts = mapAttrs (name: {
          enable,
          hostName,
          serverAliases,
          ...
        }:
          mkIf enable {
            forceSSL = true;
            enableACME = true;
            serverAliases = ["www.${hostName}"] ++ serverAliases ++ map (domain: "www.${domain}") serverAliases;
            root = config.users.users.${name}.home;
            extraConfig = ''
              index index.php index.html;
              default_type text/plain;
              add_header X-Content-Type-Options nosniff;
              rewrite ^/(content|site|kirby)/(.*)$ /error last;
              rewrite ^/\.(?!well-known/) /error last;
              rewrite ^/(?!app\.webmanifest)[^/]+$ /index.php last;
            '';
            locations."/".extraConfig = ''try_files $uri $uri/ /index.php$is_args$args;'';
            locations."~ \.php$".extraConfig = ''
              try_files $uri =404;
              fastcgi_split_path_info ^(.+\.php)(/.+)$;
              fastcgi_pass unix:${config.services.phpfpm.pools.${name}.socket};
              include ${pkgs.nginx}/conf/fastcgi.conf;
            '';
          })
        cfg.sites;

        fileSystems = mapAttrs' (name: {
          root,
          package,
          ...
        }: {
          name = "${root}/kirby"; # config.users.users.${name}.home doesnt work here cause infinite recursion encountered
          value = {
            device = "${package}";
            fsType = "none";
            options = ["bind" "ro"];
          };
        }) (filterAttrs (_name: {enable, ...}: enable) cfg.sites);
      };
    };
  };
}
