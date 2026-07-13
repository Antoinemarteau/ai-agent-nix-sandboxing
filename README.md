# ai-agent-nix-sandboxing

A reproducible agentic development environment for Julia projects on Linux,
based on nix, tmux and direnv. Currently, it provides the Claude and Kaimon CLI
as well as Julia REPL, sandboxed in different Linux "user namespaces".

This repository facilitates using coding agents in a reproducible, personalized
and safer manner, on local machine or remotely controlled via ssh.
It has the following structure:
```sh
.   # everyday development folders
├── agentshome/      # single agent-writeable root (agent data + projects)
│   ├── projects/    # Folder containing all development projects
│   ├── .envrc       # direnv config. (automatically activate dev. environment on cd)
│   ├── .claude/     # agent specific Claude config
│   ├── .config/
│   │   ├── kaimon/
│   │   └── zsh/     # sandboxed shell config
│   └── .julia/      # agent specific julia folder
│       └── startup.jl
│
│   # dev. environment definition and personalization
├── nix_src/         # nix code for the development environment
├── README.md
└── .hosthome/       # out-of-sandbox shell personalization
    └── .config/
       └── tmux/default-session.conf # user-editable tmux session layout
```
`nix` and `direnv` are the only software needed already installed. The
objective of this repo is that everything else is automatically installed in a
reproducible way upon cloning it, except what's in `.julia` and `.claude`
folders config and your projects, that you populate yourself.

The sandboxes can be run from an unprivileged environment (although root
privilege is needed to install `nix` and `direnv`). The sandboxed coding tools
can only write into `agentshome/` (which holds `projects/` and the agent data).

> [!WARNING]
> I have no security background training, there is no security guarantee. I would only
> use fully privileged sandboxed agents from an independent machine with no
> (access to) sensitive data, and commit through an independent forge (Github)
> account using independent secrets (e.g. ssh keys).


## Setup

Before starting, you will need [`nix`](https://nixos.org/download/) and
optionally [`direnv`](https://direnv.net/) (recommended) installed on your
machine.

Clone the repository. Change the hard-coded
```nix
devshellRoot = "/home/antoine/prog/ai-agent-sandboxing";
```
variable in the `nix_src/flake.nix` file, to the actual absolute path the repo.

Then enable `direnv` from within `agentshome/`
```bash
cd agentshome
direnv allow
```
Entering any project under `agentshome/projects/` now puts the sandboxed tools on
`PATH` automatically.

If `nix-direnv` is not installed on the machine, install it at user level for
faster cached reloads (optional but recommended)
```bash
nix profile install nixpkgs#nix-direnv
echo 'source $HOME/.nix-profile/share/nix-direnv/direnvrc' >> ~/.config/direnv/direnvrc
```

### Ubuntu setup

Ubuntu (23.10+) by default [restricts unprivileged user
namespaces](https://etbe.coker.com.au/2024/04/24/ubuntu-24-04-bubblewrap/) via
apparmor, so bubblewrap fails with `bwrap: setting up uid map: Permission
denied`. To fix it, run
```bash
sudo cp nix_src/apparmor/bwrap-userns-restrict /etc/apparmor.d/
sudo apparmor_parser -r -W /etc/apparmor.d/bwrap-userns-restrict
```
This apparmor config for bwrap is the same as the [default official bwrap
userns profile,
](https://gitlab.com/apparmor/apparmor/-/blob/master/profiles/apparmor/profiles/extras/bwrap-userns-restrict)
except it also works for the nix provided bwrap binaries.


## Usage

Create a project directory, clone what you need, `cd` into.
```bash
mkdir agentshome/projects/my_project
git clone <url> agentshome/projects/my_project # don't do that from within agentshome/
cd agentshome/projects/my_project
```

Then, from the project folder, start (or restart) the `tmux` development session
```bash
new_agent_session
```
On a host without `direnv`, load the environment first and then launch a session
```bash
nix develop <devshellRoot>/nix_src
new_agent_session
```

This creates a tmux session with 4 windows:
- kaimon: runs sandboxed Kaimon CLI, `jailed-kaimon`
- shell: runs a sandboxed terminal, `jailed-shell`
- claude: runs sandboxed claude-code CLI `jailed-claude`
- repl: runs sandboxed Julia REPL serving Kaimon, `jailed-julia`

This default session can be personalized by modifying `.hosthome/.config/tmux/default-session.conf`.

On the first session you ever create, `.julia` and other configs are empty, so you need to:
- Go to the repl window and wait Kaimon install to be finished.
- Go to kaimon window and launch `jailed-kaimon` to setup it, choose "Lax" mode (filtering who acceses Kaimon is pointless since it is sandboxed)
- Exit Claude, run `claude-connect-kaimon` from the shell to connect the MCP
- launch `jailed-claude` again (or `yolo-jailed-claude`) and login
Claude should then be ready to pass Kaimon's `usage_quiz` and read `usage_instructions`.
By default, Claude's login info should be stored in `agentshome/.claude/.credentials.json`.

On remote machine, `yolo-jailed-claude` can be used, it is a directory jailed
Claude with unrestricted network access.

To return to the development session later, do not re-run `new_agent_session`
(it kills and recreates the session and all existing agents), but
```bash
attach_agent_session
```
from the folder the session was started from.

Or, manually
```bash
tmux -L julia_agents ls # see live sessions
tmux -L julia_agents attach -t <session>
```
since the session is named after the folder.\
The non-default tmux socket `julia_agents` is used because the host tmux config
is overwritten with one provided from nix, for use on remote machine.

Only one Kaimon server/CLI can be used simultaneously, so you can kill the
first window if you launch a new tmux session (via `new_agent_session`) in
another sub-project.

## Security warning

This development environment gives Claude strong permission
(--dangerously-skip-permisson) by default. Treat the whole `agentshome/` tree
(agent data and `projects/`) as untrusted: development tools that may run
arbitrary code from files added in these folders (e.g. `git` with .git/ hooks)
should not be used within them.

As a guard against that mistake, a list of common host dev tools — `git`, `gh`,
`julia`, `claude`, `kaimon`, `make`, `python`, `pip`, `uv`, `conda`, `node`,
`npm`, `docker`, `apt` (see `guardedHostTools` in `flake.nix`) — is shadowed
inside the devShell: they refuse to run anywhere under the `agentshome/` tree.
It is a footgun-reducer, not a security boundary: not all dev tools are
shadowed, and absolute paths (`/usr/bin/git`) or tools that embed git (libgit2,
`gh`) bypass it.


### Git identity and GitHub token

To give a git identity for the agent, set name and email in
`agentshome/.gitconfig`. If you want it to pull/push, create
`agentshome/.git-credentials` with a GitHub [fine-grained Personal Access Token
(PAT)](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token):
```bash
echo 'https://x-access-token:github_pat_{YOUR-TOKEN-HERE}@github.com' > agentshome/.git-credentials
chmod 600 agentshome/.git-credentials
```
Make sure to not commit .git-credentials to git.

## Technical details

The tool is developed using nix and only requires installing the [nix package
manager](https://nixos.org/download/) (it is a "nix flake"). The user
namespaces are created by
[bubblewrap](https://github.com/containers/bubblewrap) via [jail.nix](https://sr.ht/~alexdavid/jail.nix/).

The design is based on this [blog from Anderson. J](https://dev.to/andersonjoseph/how-i-run-llm-agents-in-a-secure-nix-sandbox-1899).

TODO folder architechture

Written with the help of Claude code.
