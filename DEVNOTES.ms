Former encryption instructions

1. Generate a dedicated SSH key for the agent. For security, this key should be
   independent from your personal keys and associated with a separate GitHub
   account used exclusively by the agent:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_agent -C "agent"
   ```

2. Create a `.sops.yaml` in the root directory with your SSH public
   key:
   ```yaml
   keys:
     - &agentkey ssh-ed25519 AAAA...your-agent-ssh-public-key... # cat ~/.ssh/id_ed25519_agent.pub
   creation_rules:
     - path_regex: \.credentials\.json
       key_groups:
         - age:
           - *agentkey
   ```

3. Encrypt your credentials to connect to Claude from where `.sops.yaml` is:
   ```bash
   WORKSPACE$ sops -e ~/.claude/.credentials.json > credentials.enc.json
   ```
   If your SSH key has a passphrase, sops will prompt for it. This assumes that
   you have connected `claude` before so that `.credentials.json` exists. The
   encrypted `credentials.enc.json` can safely be put in a git repository.

