{
  description = "passage-hm: passage (pass with age, SSH keys as identities) for Home Manager: packages, PASSAGE_* variables, a non-destructive store bootstrap";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # Only for the module-eval check; consumers already carry home-manager and should `follows` it.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      lib = nixpkgs.lib;
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAll = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      homeManagerModules.default = import ./nix/module.nix;

      checks = forAll (pkgs:
        let
          hm = extra: (home-manager.lib.homeManagerConfiguration {
            inherit pkgs;
            modules = [ self.homeManagerModules.default { home = { username = "t"; homeDirectory = "/home/t"; stateVersion = "24.11"; }; } extra ];
          }).config;
          on = hm { programs.passageStore.enable = true; };
          off = hm { };
          v = on.home.sessionVariables;
        in
        {
          # Under Home Manager: nothing by default; on, the variables point at the store, the SSH key and the in-store recipients file.
          module-eval =
            assert !(off.home.sessionVariables ? PASSAGE_DIR) && !(off.home.activation ? passageBootstrap);
            assert v.PASSAGE_DIR == "/home/t/.passage/store" && v.PASSAGE_IDENTITIES_FILE == "/home/t/.ssh/id_ed25519";
            assert v.PASSAGE_RECIPIENTS_FILE == "/home/t/.passage/store/.age-recipients";
            assert lib.any (p: lib.hasPrefix "passage" (p.name or "")) on.home.packages;
            pkgs.runCommand "passage-hm-module-eval" { } "touch $out";

          # The design works: an SSH ed25519 key is the age identity, its .pub (seeded by the bootstrap) is the recipient,
          # an entry round-trips, the bootstrap never overwrites an existing recipients file, and entry names are plaintext paths.
          roundtrip = pkgs.runCommand "passage-hm-roundtrip" { nativeBuildInputs = [ pkgs.passage pkgs.openssh pkgs.git pkgs.bash ]; } ''
            export HOME=$TMPDIR/h; mkdir -p $HOME/.ssh
            ssh-keygen -q -t ed25519 -N "" -f $HOME/.ssh/id_ed25519
            export PASSAGE_DIR=$HOME/.passage/store PASSAGE_IDENTITIES_FILE=$HOME/.ssh/id_ed25519 PASSAGE_RECIPIENTS_FILE=$HOME/.passage/store/.age-recipients
            DRY_RUN_CMD=
            boot() { ${builtins.replaceStrings [ "/home/t" ] [ "$HOME" ] on.home.activation.passageBootstrap.data}
            }
            boot
            cmp $HOME/.ssh/id_ed25519.pub $PASSAGE_RECIPIENTS_FILE
            # an existing recipients file (another machine's key added) is left alone
            cp $PASSAGE_RECIPIENTS_FILE before; echo "# another machine" >> $PASSAGE_RECIPIENTS_FILE; cp $PASSAGE_RECIPIENTS_FILE edited
            boot; cmp edited $PASSAGE_RECIPIENTS_FILE; cp before $PASSAGE_RECIPIENTS_FILE
            printf 's3cret\n' | passage insert -m example.com/me >/dev/null
            [ "$(passage show example.com/me)" = s3cret ]
            [ -f $PASSAGE_DIR/example.com/me.age ]
            touch $out
          '';
        });
    };
}
