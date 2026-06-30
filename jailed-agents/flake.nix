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
      # Store claude config and session state in the project directory
      #(set-env "CLAUDE_CONFIG_DIR" (noescape "\"$PWD/.claude\""))
    ];

    makeJailedClaude = { extraPkgs ? [] }: jail "jailed-claude" claude-pkg (with jail.combinators; (
      commonJailOptions ++ [
        (add-pkg-deps commonPkgs)
        (add-pkg-deps extraPkgs)
      ]));

  in
  {
    lib = {
      inherit makeJailedClaude;
    };

    devShells.default = pkgs.mkShell {
      packages = [
        (makeJailedClaude {})
      ];
    };
  });
}
