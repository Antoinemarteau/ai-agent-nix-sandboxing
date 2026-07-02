{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    jailed-agents.url = "path:/home/antoine/prog/ai-agent-sandboxing/jailed-agents";
  };

  outputs = { self, nixpkgs, flake-utils, home-manager, jailed-agents, ... }:
  flake-utils.lib.eachDefaultSystem (system:
  let
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    devshellRoot = "/home/antoine/prog/ai-agent-sandboxing";
    devshellUser = "agent";

    devshellHome = import ./devshell-home.nix { inherit pkgs home-manager devshellRoot devshellUser; };

    # Minimal tmux server config
    tmuxServerConf = pkgs.writeText "devshell-tmux.conf" ''
      set-option -g exit-empty off
      set-option -g default-shell ${pkgs.zsh}/bin/zsh
      set-environment -g ZDOTDIR ${devshellRoot}/.home/.config/zsh
    '';

  in
  {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        pkgs.nixd
        pkgs.zsh
        (pkgs.writeShellScriptBin "claude" ''exec jailed-claude "$@"'')
        (pkgs.writeShellScriptBin "yolo-claude" ''exec jailed-claude --dangerously-skip-permissions "$@"'')
        (pkgs.writeShellScriptBin "jail_debuging"   ''exec jailed-shell "$@"'')

        (jailed-agents.lib.${system}.makeJailedClaude {
          inherit devshellRoot;
          extraPkgs = [ ];
        })

        (jailed-agents.lib.${system}.makeJailedShell {
          inherit devshellRoot;
          extraPkgs = [ claude-code ];
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

        export DEVSHELL_ROOT=${pkgs.lib.escapeShellArg devshellRoot}
        mkdir -p "$DEVSHELL_ROOT/.claude"

        # Activate home-manager config into a local .home dir (never touches real $HOME).
        mkdir -p "$DEVSHELL_ROOT/.home"
        HOME="$DEVSHELL_ROOT/.home" USER=${devshellUser} HOME_MANAGER_BACKUP_EXT=bak \
          ${devshellHome.activationPackage}/activate

        # Create or reset the tmux session. -L creates an independant tmux server.
        tmux -L julia-agent-dev kill-server 2>/dev/null || true
        tmux -L julia-agent-dev -f ${tmuxServerConf} start-server
        tmux -L julia-agent-dev new-session -s julia_agents
      '';
    };
  });
}
