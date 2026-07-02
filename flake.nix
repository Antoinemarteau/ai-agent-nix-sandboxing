{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jailed-agents.url = "path:./jailed-agents";
  };

  outputs = { self, nixpkgs, flake-utils, home-manager, jailed-agents, ... }:
  flake-utils.lib.eachDefaultSystem (system:
  let
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    # Variable required to be set to the repository root, containing the current file
    devshellRoot = "/home/antoine/prog/ai-agent-sandboxing";
    # Variables that can be optionally modified
    devshellUser       = "agent";
    devshellHomeFolder = ".home";
    tmuxServer         = "julia-agent-dev";
    tmuxSession        = "julia_agents";

    # home manager configuration for tmux, zsh, julia, etc.
    devshellHomeManager = import ./devshell-home.nix { inherit pkgs home-manager devshellRoot devshellUser devshellHomeFolder; };
    homeDirectory = devshellHomeManager.config.home.homeDirectory;
    configFile = devshellHomeManager.config.xdg.configFile;

  in
  {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        pkgs.nixd
        pkgs.zsh
        (pkgs.writeShellScriptBin "claude" ''exec jailed-claude "$@"'')
        (pkgs.writeShellScriptBin "yolo-claude" ''exec jailed-claude --dangerously-skip-permissions "$@"'')
        (pkgs.writeShellScriptBin "kaimon" ''exec jailed-kaimon "$@"'')
        (pkgs.writeShellScriptBin "claude-connect-kaimon" ''exec jailed-claude mcp add --transport http --scope user kaimon http://localhost:2828/mcp'')


        (jailed-agents.lib.${system}.makeJailedClaude {
          inherit devshellRoot;
          extraPkgs = [ ];
        })

        (jailed-agents.lib.${system}.makeJailedShell {
          inherit devshellRoot homeDirectory;
          extraPkgs = [ claude-code ];
        })

        (jailed-agents.lib.${system}.makeJailedJulia {
          inherit devshellRoot homeDirectory;
          extraPkgs = [ ];
        })

        (jailed-agents.lib.${system}.makeJailedKaimon {
          inherit devshellRoot homeDirectory;
          extraPkgs = [ ];
        })

      ];

      shellHook = ''
        # require tmux
        if ! command -v tmux >/dev/null 2>&1; then
          echo "ERROR: tmux is not installed on the host — install it via your OS package manager" >&2
          exit 1
        fi

        # Refuse to run inside any other tmux session — new-session cannot attach when nested.
        if [ -n "''${TMUX:-}" ]; then
          echo "ERROR: cannot run nix develop from inside a tmux session — detach first (Ctrl-b d)" >&2
          exit 1
        fi

        mkdir -p ${devshellRoot}/.claude

        # Activate home-manager config into a local .home dir (never touches real $HOME).
        mkdir -p ${homeDirectory}
        HOME=${homeDirectory} USER=${devshellUser} HOME_MANAGER_BACKUP_EXT=bak \
          ${devshellHomeManager.activationPackage}/activate

        # Create or reset the tmux session. -L creates an independant tmux server.
        tmux -L ${tmuxServer} kill-server 2>/dev/null || true
        tmux -L ${tmuxServer} -f ${configFile."tmux/tmux.conf".source} new-session -s ${tmuxSession}
      '';
    };
  });
}
