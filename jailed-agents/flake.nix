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
    julia-pkg = pkgs.julia-bin;
    claude-pkg = llm-agents.packages.${system}.claude-code;
    #opencode-pkg = llm-agents.packages.${system}.opencode;

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
      (add-pkg-deps commonPkgs)
    ];

    claudeConfigBinds = devshellRoot: with jail.combinators; [
      (rw-bind (noescape "\"${devshellRoot}/.claude\"") (noescape "~/.claude"))
      (rw-bind (noescape "\"${devshellRoot}/.claude/.claude.json\"") (noescape "~/.claude.json"))
    ];

    juliaDepotBinds = homeDirectory: with jail.combinators; [
      (rw-bind (noescape "\"${homeDirectory}/.julia\"") (noescape "~/.julia"))
    ];

    # for Kaimon <-> Julia communication
    kaimonCacheBinds = homeDirectory: with jail.combinators; [
      (rw-bind (noescape "\"${homeDirectory}/.cache/kaimon\"") (noescape "~/.cache/kaimon"))
    ];

    kaimonConfigBinds = homeDirectory: with jail.combinators; [
      (rw-bind (noescape "\"${homeDirectory}/.config/kaimon\"") (noescape "~/.config/kaimon"))
    ];

    # script ensuring all jailed programs are launched from within the root directory
    assertInDevshell = { name, devshellRoot }: ''
      set -e
      case "$(realpath "$PWD")/" in
        "$(realpath "${devshellRoot}")/"*) ;;
        *)
          echo "${name}: must be run from within ${devshellRoot}" >&2
          echo "  current: $PWD" >&2
          exit 1
          ;;
      esac
    '';

    withClaudeConfigInit = { name, inner, devshellRoot }: pkgs.writeShellScriptBin name ''
      ${assertInDevshell { inherit name devshellRoot; }}
      mkdir -p ${devshellRoot}/.claude
      # .claude.json needs to be created within the jail to be valid, but it is
      # linked to a temporary folder (the jail's home). This pre hook makes sure
      # that a writable .claude.json exists both on the host and in the jail.
      touch ${devshellRoot}/.claude/.claude.json
      exec ${inner}/bin/${name}-inner "$@"
    '';

    withJuliaInit = { name, inner, devshellRoot, homeDirectory }: pkgs.writeShellScriptBin name ''
      ${assertInDevshell { inherit name devshellRoot; }}
      mkdir -p ${homeDirectory}/.julia
      mkdir -p ${homeDirectory}/.cache/kaimon/sock
      exec ${inner}/bin/${name}-inner "$@"
    '';

    withKaimonInit = { name, inner, devshellRoot, homeDirectory }: pkgs.writeShellScriptBin name ''
      ${assertInDevshell { inherit name devshellRoot; }}
      mkdir -p ${homeDirectory}/.julia
      mkdir -p ${homeDirectory}/.cache/kaimon/sock
      mkdir -p ${homeDirectory}/.config/kaimon
      exec ${inner}/bin/${name}-inner "$@"
    '';

    makeJailedShell = { extraPkgs ? [], devshellRoot, homeDirectory }:
      let
        inner = jail "jailed-shell-inner" pkgs.bashInteractive (with jail.combinators;
          commonJailOptions ++
            # get's everything we bind, for debugging purpose.
            (claudeConfigBinds devshellRoot) ++
            (juliaDepotBinds homeDirectory) ++
            (kaimonConfigBinds homeDirectory) ++
            (kaimonCacheBinds homeDirectory) ++ [
            (add-pkg-deps extraPkgs)
          ]);
      in withClaudeConfigInit { name = "jailed-shell"; inherit inner devshellRoot; };

    makeJailedClaude = { extraPkgs ? [], devshellRoot }:
      let
        inner = jail "jailed-claude-inner" claude-pkg (with jail.combinators;
          commonJailOptions ++ (claudeConfigBinds devshellRoot) ++ [
            (add-pkg-deps extraPkgs)
          ]);
      in withClaudeConfigInit { name = "jailed-claude"; inherit inner devshellRoot; };

    makeJailedJulia = { extraPkgs ? [], devshellRoot, homeDirectory }:
      let
        inner = jail "jailed-julia-inner" julia-pkg (with jail.combinators;
          commonJailOptions ++
          (juliaDepotBinds homeDirectory) ++
          (kaimonCacheBinds homeDirectory) ++
          [
            (add-pkg-deps extraPkgs)
          ]);
      in withJuliaInit { name = "jailed-julia"; inherit inner devshellRoot homeDirectory; };

    makeJailedKaimon = { extraPkgs ? [], devshellRoot, homeDirectory }:
      let
        kaimonLauncher = pkgs.writeShellScriptBin "kaimon" ''
          exec ~/.julia/bin/kaimon "$@"
        '';
        inner = jail "jailed-kaimon-inner" kaimonLauncher (with jail.combinators;
          commonJailOptions ++
          (juliaDepotBinds homeDirectory) ++
          (kaimonCacheBinds homeDirectory) ++
          (kaimonConfigBinds homeDirectory) ++
          [
            (add-pkg-deps [ julia-pkg ])
            (add-pkg-deps extraPkgs)
          ]);
      in withKaimonInit { name = "jailed-kaimon"; inherit inner devshellRoot homeDirectory; };

    #makeJailedOpencode = { extraPkgs ? [] }: jail "jailed-opencode" opencode-pkg (with jail.combinators; (
    #  commonJailOptions ++ [
    #    # Give it a safe spot for its own config and cache.
    #    # This also lets it remember things between sessions.
    #    (readwrite (noescape "~/.config/opencode"))
    #    (readwrite (noescape "~/.local/share/opencode"))
    #    (readwrite (noescape "~/.local/state/opencode"))
    #    (add-pkg-deps extraPkgs)
    #  ]));

  in
  {
    lib = {
      inherit makeJailedClaude;
      inherit makeJailedShell;
      inherit makeJailedJulia;
      inherit makeJailedKaimon;
    };

  });
}
