# `.devcontainer/zshrc.d/`

Interactive-zsh drop-ins for your project. Core sources every file here on shell
start, **after** oh-my-zsh and any feature drop-ins — so this is where project
prompt tweaks, aliases, functions, and keybinds go. Edits are picked up by any
**new** terminal, no rebuild (already-open shells need `source ~/.zshrc`).

Two lanes:

| File | Scope | Committed? | Order |
|---|---|---|---|
| `*.zsh` | project / team | **yes** — commit these | after features |
| `.overrides.zsh` | personal (your machine) | **no** — gitignored | **last, wins** |

- Put shared config the whole team should get in a committed `*.zsh` (e.g.
  `10-team.zsh`). Numeric prefixes control order among project files.
- Put your own personal tweaks in `.overrides.zsh`. It's gitignored (see the
  `.gitignore` here) and sourced last, so it overrides both features and project
  files without you committing personal preferences. Copy `.overrides.zsh.example`
  to `.overrides.zsh` to start.

Ordering, first to last (last wins):

```
oh-my-zsh + theme → feature drop-ins → project *.zsh → .overrides.zsh
```
