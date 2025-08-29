Just a simple flake to provide the CMS [Kirby](https://github.com/getkirby/kirby) as a NixOS module, including packages for the latest versions of Kirby 3, 4, and 5.

  > [!note]
  > Kirby is not free to use. To use Kirby in production, you need to purchase a [license](https://getkirby.com/license).

## What this flake does
  - Creates a system user and group for each instance
  - Mounts the package from your nix-store into the root directory (e.g. ```/var/www/<name>/kirby```) as read-only
  - Preconfigures the ```services.nginx.virtualHosts.<hostName>``` entry for each instance
  - Preconfigures and starts a dedicated PHP-FPM pool for each instance

## Usage

### Flake Reference
Add Kirby to your flake inputs and ensure you're following your own `nixpkgs`.
  > [!note]
  > This flake **should** work with any recent NixOS version and system.  
  > However, it has only been tested with **NixOS 25.05** on `x86_64-linux` at this point.

```nix
# flake.nix
inputs = {
  nixpkgs.url = "github:NixOs/nixpkgs/<your-version>";
  kirby-cms = {
    url = "github:277292/kirby-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

Load the module and overlay:
```nix
# flake.nix
outputs = {self, nixpkgs, kirby-cms, ...}: {
  nixosConfigurations.joes-server = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ./configuration.nix

      # Kirby CMS module
      kirby-cms.nixosModules.kirby

      # Overlay to make Kirby packages available
      ({config, pkgs, ...}: {
        nixpkgs.overlays = [kirby-cms.overlays.kirby];

        # Explicitly allow Kirby, as it is unfree
        nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) ["kirby"];
      })
    ];
  };
};
```

### Configuration
```nix
# configuration.nix
{config, pkgs, ...}: {
  # Ensure that a default package is set and/or specify one per instance.
  kirby-cms.default.package = pkgs.kirby4;
  kirby-cms.sites = {
    "getKirby.com" = {};
    example2 = {};
  };

  # Ensure that nginx is enabled.
  services.nginx.enable = true;
};
```
This will create two Kirby instances in ```/var/www/getKirby.com``` and ```/var/www/example2``` using Kirby 4.

To disable SSL and ACME (e.g. for local development):
```nix
# configuration.nix
{config, lib, ...}: let cfg = config.kirby-cms; in {
  kirby-cms = {...};

  services.nginx.virtualHosts."${cfg.sites.<name>.hostName}" = {
    forceSSL = lib.mkForce false;
    enableACME = lib.mkForce false;
  };
}
```

### Options *with defaults*
```kirby-cms.default.root = "/var/www"```

```kirby-cms.default.timezone = "UTC"```

```kirby-cms.default.package = null```

```kirby-cms.sites.<name>.enable = true```

```kirby-cms.sites.<name>.hostName = <name>```

```kirby-cms.sites.<name>.serverAliases = []```

```kirby-cms.sites.<name>.root = "${cfg.default.root}/<name>"```

```kirby-cms.sites.<name>.timezone = cfg.default.timezone```

```kirby-cms.sites.<name>.package = cfg.default.package```

For more description and examples, see the [flake.nix](https://github.com/277292/kirby-flake/blob/main/flake.nix)

### Disclaimer
This flake is only a wrapper for integrating Kirby CMS into Nix.  
I am not affiliated with the Kirby project, and this repository is not endorsed by or connected to the creators of Kirby. For licensing, usage terms, and commercial support, see [getkirby.com](https://getkirby.com/).

### Contributing
Feel free to open an issue or submit a pull request if you encounter a problem or have an idea for improvement — contributions related to this flake are very welcome.
