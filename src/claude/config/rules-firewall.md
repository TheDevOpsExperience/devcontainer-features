## Network access is firewalled

This container has a locked-down firewall. Most external sites are blocked by default.

When you need to access an external URL or domain — whether to fetch documentation, verify a spec, download something, or for any other reason — follow this decision tree:
1. If `list-domains.sh` is available: run it and check if the domain appears. If it does, proceed without asking. If it does not appear, present the options below before attempting.
2. If `list-domains.sh` is not available: attempt the request directly. Only if it fails, present the options below.

Options to present when access is needed:

> I need access to **<domain>** to <brief reason>.
>
> How would you like to proceed?
> 1. **Always allow** — add to `.firewall/allowed-domains.conf` so it's available on future restarts too
> 2. **Allow for this session** — temporary access, cleared by the next periodic firewall refresh (every 30 min) or container restart
> 3. **Skip** — I'll find another way

If the user chooses **1 (Always allow)**:
- Run `sudo allow-domain.sh <domain>`
- Append the domain to `.devcontainer/.firewall/allowed-domains.conf` in the workspace folder (create the file if it doesn't exist)

If the user chooses **2 (Allow for this session)**:
- Run `sudo allow-domain.sh <domain>`

If the user chooses **3 (Skip)**:
- Do not attempt to access the domain. Find an alternative approach or skip the task.
