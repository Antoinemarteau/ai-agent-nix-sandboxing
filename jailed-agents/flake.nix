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

    claudeConfigBinds = with jail.combinators; [
      (rw-bind (noescape "\"$JAILED_CLAUDE_CONFIG\"") (noescape "~/.claude"))
      (rw-bind (noescape "\"$JAILED_CLAUDE_CONFIG/.claude.json\"") (noescape "~/.claude.json"))
    ];

    # srt sets HTTP_PROXY et al. in its child's environment, needs to be
    # forwarded to the jail
    srtProxyEnvForwards = with jail.combinators; map try-fwd-env [
      "HTTP_PROXY" "http_proxy"
      "HTTPS_PROXY" "https_proxy"
      "NO_PROXY" "no_proxy"
      "ALL_PROXY" "all_proxy"
    ];

    # Domains Claude Code needs (source https://code.claude.com/docs/en/network-config)
    defaultAllowedDomains = [
      "api.anthropic.com"         # token API
      "claude.ai"                 # subscription
      "platform.claude.com"       # Console (API-key)
      "raw.githubusercontent.com" # release notes feed
    ];

    srtSettings = allowedDomains: pkgs.writeText "srt-settings.json" (builtins.toJSON {
      network = {
        inherit allowedDomains;
        deniedDomains = []; # strictly deny everything there
        strictAllowlist = true;
      };
      filesystem = {
        disabled = true;
        denyRead = [];
        allowWrite = [];
        denyWrite = [];
      };
    });

    # srt runs an HTTP/SOCKS proxy inside its own bwrap (unshare-net), then
    # invokes `cmd` in that isolated netns. The inner jail must inherit the
    # netns (jail.nix's `network` combinator uses --share-net) and forward
    # the proxy env (`srtProxyEnvForwards`). Returns a shell command string,
    # not a derivation — meant to be spliced into an `exec` line.
    wrapWithSrt = { allowedDomains, cmd }:
      "${pkgs.sandbox-runtime}/bin/srt -s ${srtSettings allowedDomains} -- ${cmd}";

    # .claude.json needs to be created within the jail to be valid, but it is
    # linked to a temporary folder (the jail's home). This pre hook makes sure
    # that a writable .claude.json exists both on the host and in the jail.
    withClaudeConfigInit = { name, cmd }: pkgs.writeShellScriptBin name ''
      set -e
      if [ -z "''${JAILED_CLAUDE_CONFIG:-}" ]; then
        echo "${name}: JAILED_CLAUDE_CONFIG must be set" >&2
        exit 1
      fi
      mkdir -p "$JAILED_CLAUDE_CONFIG"
      touch "$JAILED_CLAUDE_CONFIG/.claude.json"
      exec ${cmd} "$@"
    '';

    makeJailedShell = { extraPkgs ? [], allowedDomains ? null }:
      let
        inner = jail "jailed-shell-inner" pkgs.bashInteractive (with jail.combinators;
          commonJailOptions ++ claudeConfigBinds ++ srtProxyEnvForwards ++ [
            (add-pkg-deps commonPkgs)
            (add-pkg-deps extraPkgs)
          ]);
        innerCmd = "${inner}/bin/jailed-shell-inner";
        cmd = if allowedDomains == null then innerCmd
              else wrapWithSrt { inherit allowedDomains; cmd = innerCmd; };
      in withClaudeConfigInit { name = "jailed-shell"; inherit cmd; };

    makeJailedClaude = { extraPkgs ? [], allowedDomains ? null }:
      let
        inner = jail "jailed-claude-inner" claude-pkg (with jail.combinators;
          commonJailOptions ++ claudeConfigBinds ++ srtProxyEnvForwards ++ [
            (add-pkg-deps commonPkgs)
            (add-pkg-deps extraPkgs)
          ]);
        innerCmd = "${inner}/bin/jailed-claude-inner";
        cmd = if allowedDomains == null then innerCmd
              else wrapWithSrt { inherit allowedDomains; cmd = innerCmd; };
      in withClaudeConfigInit { name = "jailed-claude"; inherit cmd; };

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
      inherit defaultAllowedDomains;
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
