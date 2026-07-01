{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    jailed-agents.url = "path:/home/antoine/prog/ai-agent-sandboxing/jailed-agents";
  };

  outputs = { self, nixpkgs, flake-utils, jailed-agents, ... }:
  flake-utils.lib.eachDefaultSystem (system:
  let
            #system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    devshellRoot = "/home/antoine/prog/ai-agent-sandboxing";
  in
  {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        pkgs.nixd
        (pkgs.writeShellScriptBin "claude" ''exec jailed-claude "$@"'')
        (pkgs.writeShellScriptBin "yolo-claude" ''exec jailed-claude --dangerously-skip-permissions "$@"'')
        (pkgs.writeShellScriptBin "jail_debuging"   ''exec jailed-bash "$@"'')

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

        # Create or reset the tmux session. -L creates an independant tmux server.
        tmux -L julia-agent-dev kill-server 2>/dev/null || true
        tmux -L julia-agent-dev new-session -s julia_agents
      '';
    };
  });
}
