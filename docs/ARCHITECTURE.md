# Packaging Architecture

```text
Build host (Windows x64, online)
        |
        +-- release: HEAD must equal the pinned source.ref SHA
        |      and the work tree plus submodules must be clean
        |      (-DevelopmentMode may pull main, but that MSI is unreleasable)
        |
        +-- upstream install.ps1 stages on the build host only
        |      uv -> python -> git -> node
        |
        +-- Build Gate
        |      delete venv, uv sync --offline --frozen --no-progress
        |      hermes.exe --version
        |      npm_config_offline node-deps proves the npm cache, then deletes node_modules
        |      payload\playwright must contain chrome.exe or headless_shell.exe
        |      proof is written to dist/build-info.json offlineProof
        |
        +-- rg + ffmpeg portable binaries
        |
        +-- enterprise defaults/bootstrap
        v
    payload/   (no build-host venv, no node_modules)
        |
        +-- WiX 5 (WixToolset.Sdk/5.0.2) recursive Files harvesting
        v
  single per-user MSI
        |
        v
%LOCALAPPDATA%\hermes
        |
        +-- deferred impersonated initializer
               Preflight hashes 8 manifest paths
               uv sync --offline --frozen --no-progress in an allowlisted environment
               then import yaml, openai before copying bin\hermes.exe
               venv\Scripts\hermes.exe --version
               copy to bin\hermes.exe and --version again
```

Only the build host may use the network. The endpoint Core path does not call upstream `install.ps1`, does not run `node` / `npm` / `npx`, and does not download package registries. Failure diagnostics stay in `%TEMP%\hermes-msi-preflight.log` and `%TEMP%\hermes-msi-initialize.log`.

## Why the Python venv is recreated on target

Windows venv launchers and interpreter metadata may contain absolute paths. Shipping a build-host venv into a different user's `%LOCALAPPDATA%` is not a reliable relocatable contract. The package therefore ships the managed Python runtime and uv cache, then materializes the venv at the final user path.

## How source preparation works

The packaging project uses a local-first source scheme. A release build requires
`src/hermes-agent` HEAD to equal the pinned `source.ref` SHA and a clean work
tree, including submodules. It does not `git pull`. `-DevelopmentMode` keeps the
old `main` + `git pull --ff-only` behavior and marks `build-info.json`
`unreleasable`. If the checkout is absent, the builder clones the configured
repository and detaches at `source.ref`. The resulting MSI contains that
snapshot; the checkout itself stays outside the MSI payload.
