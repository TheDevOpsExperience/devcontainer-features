# Devcontainer Rules

You are running inside a containerized developer sandbox.

## Installing packages

Do NOT use `sudo apt-get` directly — it is not allowed. Use the wrapper script instead:

```
sudo install-package.sh <package1> [package2] ...
```

Examples:
- `sudo install-package.sh python3`
- `sudo install-package.sh openjdk-17-jdk maven`

The wrapper validates package names and rejects flags.
