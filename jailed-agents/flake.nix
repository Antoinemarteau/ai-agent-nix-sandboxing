{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
    llm-agents.url = "github:numtide/llm-agents.nix";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, jail-nix, llm-agents, flake-utils, ... }:
  flake-utils.lib.eachDefaultSystem (system:
  let
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    jail = jail-nix.lib.init pkgs;

    # I'm using crush and opencode, but you could swap in others.
    opencode-pkg = llm-agents.packages.${system}.opencode;
    claude-pkg = llm-agents.packages.${system}.claude-code;

    commonPkgs = with pkgs; [
      bashInteractive
      curl
      wget
      jq
      git
      which
      ripgrep
      gnugrep
      gawkInteractive
      ps
      findutils
      gzip
      unzip
      gnutar
      diffutils
    ];

    commonJailOptions = with jail.combinators; [
      network
      time-zone
      no-new-session
      mount-cwd
      (fwd-env "USER") # important to be able to re-use the .claude.json, which depend on the user
    ];

    claudeConfigBinds = devshellRoot: with jail.combinators; [
      (rw-bind (noescape "\"${devshellRoot}/.claude\"") (noescape "~/.claude"))
      (rw-bind (noescape "\"${devshellRoot}/.claude/.claude.json\"") (noescape "~/.claude.json"))
    ];

    # .claude.json needs to be created within the jail to be valid, but it is
    # linked to a temporary folder (the jail's home). This pre hook makes sure
    # that a writable .claude.json exists both on the host and in the jail.
    withClaudeConfigInit = { name, inner, devshellRoot }: pkgs.writeShellScriptBin name ''
      set -e
      case "$(realpath "$PWD")/" in
        "$(realpath "${devshellRoot}")/"*) ;;
        *)
          echo "${name}: must be run from within ${devshellRoot}" >&2
          echo "  current: $PWD" >&2
          exit 1
          ;;
      esac
      mkdir -p ${devshellRoot}/.claude
      touch ${devshellRoot}/.claude/.claude.json
      exec ${inner}/bin/${name}-inner "$@"
    '';

    makeJailedShell = { extraPkgs ? [], devshellRoot }:
      let
        inner = jail "jailed-shell-inner" pkgs.bashInteractive (with jail.combinators;
          commonJailOptions ++ (claudeConfigBinds devshellRoot) ++ [
            (add-pkg-deps commonPkgs)
            (add-pkg-deps extraPkgs)
          ]);
      in withClaudeConfigInit { name = "jailed-shell"; inherit inner devshellRoot; };

    makeJailedClaude = { extraPkgs ? [], devshellRoot }:
      let
        inner = jail "jailed-claude-inner" claude-pkg (with jail.combinators;
          commonJailOptions ++ (claudeConfigBinds devshellRoot) ++ [
            (add-pkg-deps commonPkgs)
            (add-pkg-deps extraPkgs)
          ]);
      in withClaudeConfigInit { name = "jailed-claude"; inherit inner devshellRoot; };

    #makeJailedOpencode = { extraPkgs ? [] }: jail "jailed-opencode" opencode-pkg (with jail.combinators; (
    #  commonJailOptions ++ [
    #    # Give it a safe spot for its own config and cache.
    #    # This also lets it remember things between sessions.
    #    (readwrite (noescape "~/.config/opencode"))
    #    (readwrite (noescape "~/.local/share/opencode"))
    #    (readwrite (noescape "~/.local/state/opencode"))
    #    (add-pkg-deps commonPkgs)
    #    (add-pkg-deps extraPkgs)
    #  ]));

  in
  {
    lib = {
      inherit makeJailedClaude;
      inherit makeJailedShell;
    };

    devShells.default = pkgs.mkShell {
      packages = [
        (makeJailedShell {})
        (makeJailedClaude {})
        #(makeJailedOpencode {})
      ];
    };
  });
}
