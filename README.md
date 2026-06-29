# ai-agent-nix-sandboxing

A tool to run coding agents within a sandboxed environment that is based on the
"user namespaces" Linux feature and can be run without host privilege.

The sandbox can be run from an unprivileged environment, still the sandboxed
agent can be given full privilege.

> [!WARNING]
> I have no security background, there is no security guarantee. I would only
> use fully privileged sandboxed agents from an independent machine with no
> (access to) sensitive data, and commit through an independent forge (Github)
> account using independent secrets (e.g. ssh keys).

## Usage



## Technical details

The tool is developed using nix and only requires installing the [nix package
manager](https://nixos.org/download/) (it is a "nix flake"). The user
namespaces are created by
[bubblewrap](https://github.com/containers/bubblewrap) via [jail.nix](https://sr.ht/~alexdavid/jail.nix/).

Written using Claude-code.
