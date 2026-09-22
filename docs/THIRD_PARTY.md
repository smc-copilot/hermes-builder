# Third-party distribution checklist

Before distributing a built MSI beyond controlled internal evaluation, review the licenses and required notices for every binary actually present in `payload/`.

At minimum review:

- uv
- Python distribution selected by uv
- Git for Windows
- Node.js and npm
- ripgrep
- ffmpeg / ffprobe build source and codec configuration
- Python packages resolved by `uv.lock`
- npm packages resolved by the repository lock file

The builder intentionally downloads third-party artifacts at build time instead of embedding them in this packaging-project ZIP.
