{ config, lib, pkgs, ... }:

# passage: a password store that is a git repo of age-encrypted files.
#
# WHY NOT `pass`, which is the better-known one. `pass` requires GPG; a machine
# that deliberately has none (no gpg binary, no secret keys, git commits signed
# with SSH via `gpg.format = "ssh"`) would have to adopt
# gnupg, a GPG key, gpg-agent and pinentry: a second key-management
# story running beside the one already chosen, to gain nothing pass has that
# passage lacks.
#
# passage is pass with age instead of GPG. Same commands, same layout, same
# property that matters here: THE DIRECTORY STRUCTURE IS THE INDEX. Entry
# names are plaintext paths, so listing which services exist never decrypts
# anything.
#
# WHY IT SUITS MORE THAN ONE MACHINE, which is the actual requirement.
#
# age accepts SSH public keys as recipients. The recipients file lists one
# ed25519 public key per machine; each machine decrypts with the private half
# it already has in ~/.ssh. NO SHARED SECRET EVER MOVES between machines —
# adding a laptop is appending a public key and re-encrypting, and removing one
# is deleting a line. With GPG the same thing means exporting a private key or
# maintaining a keyring, which is the step people get wrong.
#
# THE COST OF THE PROPERTY THAT MAKES IT USEFUL.
#
# Entry names are plaintext, and that cuts both ways. It is why a domain
# inventory costs no decryption — and it means anyone who can read the REPO
# learns every service in it without breaking any encryption. The values are
# safe; the shape is not. So the remote must be private, and "private repo on a
# host someone else operates" is a threat-model decision to make deliberately,
# not a default to drift into. A self-hosted remote avoids the question.
#
# MIGRATION FROM APPLE PASSWORDS is the one unavoidable rough edge. Neither
# pass nor passage registers as a macOS credential provider, so Passwords.app's
# "Export All Items to App" cannot see them; only "Export All Passwords to
# File" can, and that writes PLAINTEXT CREDENTIALS TO DISK. With FileVault on
# that is defensible rather than reckless, but the file must be
# deleted the moment the import finishes and must never reach a git index.
# That step is the user's to run; nothing in this module automates it.

let
  cfg = config.programs.passageStore;
  storeDir = cfg.storeDir;
  identity = cfg.identity;
in
{
  options.programs.passageStore = {
    enable = lib.mkEnableOption "passage (pass with age instead of GPG), age, pass-import, the PASSAGE_* session variables and a non-destructive store bootstrap";
    storeDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.passage/store";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.passage/store"'';
      description = "PASSAGE_DIR: the store (a git repo of age-encrypted files; its remote is yours to add).";
    };
    identity = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.ssh/id_ed25519";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.ssh/id_ed25519"'';
      description = "PASSAGE_IDENTITIES_FILE: an SSH private key used directly as the age identity; its .pub seeds the recipients file once.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      passage
      # `age` on its own, because the useful operations around a store are not
      # passage subcommands: adding a machine is `age-keygen`/`age -R`, and
      # re-encrypting after a recipient change is plain age.
      age
      # Reads the Apple Passwords CSV. A pass EXTENSION, so it is
      # `passExtensions.pass-import` and not a top-level package — it writes a
      # pass-shaped tree, which is the same layout passage reads. Kept declared
      # so the migration does not need a one-off `nix shell` nothing records.
      passExtensions.pass-import
    ];

    home.sessionVariables = {
      PASSAGE_DIR = storeDir;
      # The SSH PRIVATE key, used directly as an age identity — no new key
      # material, and no agent to configure. age reads OpenSSH keys natively.
      PASSAGE_IDENTITIES_FILE = identity;
      # Every machine that may decrypt, one public key per line. Checked into
      # the store repo on purpose: it is public-key material, and keeping it
      # beside the entries is what makes "who can read this" answerable from the
      # repo alone.
      PASSAGE_RECIPIENTS_FILE = "${storeDir}/.age-recipients";
    };

    # The store is a git repo and its remote is not this module's business — a
    # secret store should not have its push target set by a config that is itself
    # public. `passage git remote add` is a deliberate one-time act.
    #
    # Bootstrap, idempotent and non-destructive: create the directory and seed
    # the recipients file with THIS machine's public key if it does not exist.
    # Never rewrites an existing recipients file, because that would silently cut
    # another machine out of the store.
    home.activation.passageBootstrap =
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        store=${lib.escapeShellArg storeDir}
        recipients="$store/.age-recipients"
        pub=${lib.escapeShellArg "${identity}.pub"}
        if [ ! -e "$recipients" ] && [ -r "$pub" ]; then
          $DRY_RUN_CMD mkdir -p "$store"
          $DRY_RUN_CMD cp "$pub" "$recipients"
        fi
      '';
  };
}
