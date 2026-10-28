# passage-hm

[passage](https://github.com/FiloSottile/passage) — `pass` with age instead of GPG — for Home Manager. An SSH
ed25519 key is the age identity, so no GPG, no new key material, and adding a machine is appending its SSH public
key to the store's `.age-recipients` and re-encrypting. Entry names are plaintext paths (a listing never decrypts),
so the store's git remote must be private.

`programs.passageStore.enable` installs `passage`, `age` and `pass-import`, sets `PASSAGE_DIR`,
`PASSAGE_IDENTITIES_FILE` and `PASSAGE_RECIPIENTS_FILE`, and at activation seeds `.age-recipients` with this
machine's public key only if the file does not exist (never rewrites it: that would cut another machine out).
The remote is yours to add (`passage git remote add …`).

```nix
inputs.passage-hm = { url = "github:bdelanghe/passage-hm"; inputs.nixpkgs.follows = "nixpkgs"; inputs.home-manager.follows = "home-manager"; };
# modules = [ passage-hm.homeManagerModules.default ];
programs.passageStore.enable = true;   # storeDir / identity are options
```

Importing from Apple Passwords means "Export All Passwords to File" — plaintext on disk. Delete it the moment the
import (`pass import`) finishes; nothing here automates that step.

## Checks

`nix flake check`: the module under Home Manager, and a round trip with a fresh SSH key through the bootstrap.
