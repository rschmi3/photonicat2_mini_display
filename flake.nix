{
  description = "Photonicat 2 display binary — patched for dynamic WAN interface detection";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Cross-compile for aarch64-linux-musl (OpenWRT target).
      # pkgsStatic gives us a musl-based toolchain; CGO_ENABLED=0 means no C
      # compiler is actually invoked — pure Go, fully static binary.
      pcat2Display = pkgs.pkgsCross.aarch64-multiplatform.pkgsStatic.buildGoModule {
        pname = "pcat2-display";
        version = "patched";
        src = pkgs.lib.cleanSourceWith {
          src = ./.;
          # Exclude the vendor/ dir so buildGoModule fetches deps itself
          # using the vendorHash below (hermetic, reproducible builds).
          filter = path: type:
            baseNameOf path != "vendor";
        };

        vendorHash = "sha256-0bGqyZIR3mbD8VN9YHW99Upt4sbcgK+owN6XNbQdwqY=";

        env.CGO_ENABLED = "0";
        ldflags = [ "-s" "-w" ];

        # The repo builds a single binary; tell Nix what it's called.
        meta.mainProgram = "photonicat2_mini_display";
      };

      host = "root@172.16.0.1";

    in {
      packages.${system} = {
        pcat2-display = pcat2Display;
        default = pcat2Display;
      };

      apps.${system} = {
        # nix run .#deploy-pcat2
        # Copies the binary to the device, backs up the existing one, installs,
        # and restarts the display service.
        deploy-pcat2 = {
          type = "app";
          program = toString (pkgs.writeShellScript "deploy-pcat2" ''
            set -euo pipefail
            BINARY="${pcat2Display}/bin/photonicat2_mini_display"
            HOST="${host}"

            echo "==> Binary: $BINARY"
            ls -lh "$BINARY"

            echo ""
            echo "==> Copying to device..."
            ${pkgs.openssh}/bin/scp "$BINARY" "$HOST:/tmp/pcat2_mini_display_new"

            echo "==> Installing on device..."
            ${pkgs.openssh}/bin/ssh "$HOST" '
              set -e
              echo "  Stopping display service..."
              /etc/init.d/pcat2-display-mini stop || true

              echo "  Backing up current binary..."
              cp /usr/bin/photonicat2_mini_display /usr/bin/photonicat2_mini_display.bak

              echo "  Installing new binary..."
              cp /tmp/pcat2_mini_display_new /usr/bin/photonicat2_mini_display
              chmod +x /usr/bin/photonicat2_mini_display
              rm /tmp/pcat2_mini_display_new

              echo "  Starting display service..."
              /etc/init.d/pcat2-display-mini start

              echo "  Done."
            '
            echo ""
            echo "==> Deployed successfully."
            echo "    To rollback: nix run .#rollback-pcat2"
          '');
        };

        # nix run .#rollback-pcat2
        # Restores the .bak binary and restarts the service.
        rollback-pcat2 = {
          type = "app";
          program = toString (pkgs.writeShellScript "rollback-pcat2" ''
            set -euo pipefail
            HOST="${host}"

            echo "==> Rolling back on device..."
            ${pkgs.openssh}/bin/ssh "$HOST" '
              set -e
              if [ ! -f /usr/bin/photonicat2_mini_display.bak ]; then
                echo "ERROR: no .bak found at /usr/bin/photonicat2_mini_display.bak"
                exit 1
              fi
              echo "  Stopping display service..."
              /etc/init.d/pcat2-display-mini stop || true

              echo "  Restoring backup..."
              cp /usr/bin/photonicat2_mini_display.bak /usr/bin/photonicat2_mini_display
              chmod +x /usr/bin/photonicat2_mini_display

              echo "  Starting display service..."
              /etc/init.d/pcat2-display-mini start

              echo "  Done."
            '
            echo ""
            echo "==> Rollback complete."
          '');
        };
      };
    };
}
