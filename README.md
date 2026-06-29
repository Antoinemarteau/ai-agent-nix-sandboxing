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

## Setup

1. Generate a dedicated SSH key for the agent. For security, this key should be
   independent from your personal keys and associated with a separate GitHub
   account used exclusively by the agent:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_agent -C "agent"
   ```

2. Create the main directory where you will put your different projects (called
   `WORKSPACE` here). Generate a [long life Claude
   token](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token),
   if you don't have one:
   ```bash
   claude setup-token
   ```

3. Create a `.sops.yaml` in your project root with your SSH public key:
   ```yaml
   keys:
     - &agentkey ssh-ed25519 AAAA...your-agent-ssh-public-key... # cat ~/.ssh/id_ed25519_agent.pub
   creation_rules:
     - path_regex: secrets\.yaml
       key_groups:
         - age:
           - *agentkey
   ```
   Create a secrets file at the root
   ```bash
   sops WORKSPACE/secrets.yaml
   # or, if you don't have sops installed
   nix-shell -p sops --run "export SOPS_AGE_SSH_PRIVATE_KEY_FILE=\"YOUR_HOME/.ssh/id_ed25519_agent\"; sops secrets.yaml"
   ```
   and the Claude token in it as follows:
   ```yaml
   CLAUDE_CODE_OAUTH_TOKEN: your-token-here
   ```
   If your SSH key has a passphrase, sops will prompt for it. This `secrets.yaml`
   file is encrypted by the ssh key, and can safely be put in a git repository.

## Usage

```bash
# from the workspace directory (uses current directory by default)
nix run github:Antoinemarteau/ai-agent-nix-sandboxing

# or from anywhere, pointing to the workspace explicitly
AGENT_WORKDIR=./WORKSPACE nix run github:Antoinemarteau/ai-agent-nix-sandboxing
```

## Technical details

The tool is developed using nix and only requires installing the [nix package
manager](https://nixos.org/download/) (it is a "nix flake"). The user
namespaces are created by
[bubblewrap](https://github.com/containers/bubblewrap) via [jail.nix](https://sr.ht/~alexdavid/jail.nix/).

Written using Claude-code.
