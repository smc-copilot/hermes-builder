# Packaging Architecture

```text
Build host (Windows x64, online)
        |
        +-- use src/hermes-agent on main + git pull --ff-only
        |      or clone configured repository/ref when absent
        |
        +-- upstream install.ps1 stages
        |      uv -> python -> git -> node
        |
        +-- uv sync --locked -> packaged uv cache
        |      build-host venv is deleted
        |
        +-- upstream node-deps -> hydrated node_modules
        |
        +-- rg + ffmpeg portable binaries
        |
        +-- enterprise defaults/bootstrap
        v
    payload/
        |
        +-- WiX 4 recursive Files harvesting
        v
  single per-user MSI
        |
        v
%LOCALAPPDATA%\hermes
        |
        +-- deferred impersonated initializer
               uv sync --offline --locked
               -> final user-path venv
```

The build host is allowed network access; the endpoint Core MSI initialization path is designed not to require package registry downloads.

## Why the Python venv is recreated on target

Windows venv launchers and interpreter metadata may contain absolute paths. Shipping a build-host venv into a different user's `%LOCALAPPDATA%` is not a reliable relocatable contract. The package therefore ships the managed Python runtime and uv cache, then materializes the venv at the final user path.

## How source preparation works

The packaging project uses a local-first source scheme. When `src/hermes-agent`
exists, the builder requires a valid Git work tree on `main`,
fast-forwards it with `git pull --ff-only`, and copies that snapshot into the
payload. If it does not exist, the builder clones the configured repository
into that path and checks out the configured fallback ref. The resulting MSI
always contains the source snapshot used by the build, while the source
checkout remains outside the MSI payload's ownership boundary.
