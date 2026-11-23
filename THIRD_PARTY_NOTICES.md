# Third-Party Notices and Provenance

## Proprietary Binaries
This repository contains no third-party proprietary binaries (such as Sysinternals or NirSoft tools). Any developer tools installed or updated by `check-tooling.ps1` are fetched directly from their official upstream package sources when explicitly requested by the user.

## Dynamic Dependencies
The `check-tooling.ps1` utility can install or update the following developer CLIs via official package managers (`winget`, `scoop`, `choco`) or vendor installers:
- `git`
- `uv`
- `python`
- `pnpm`
- `npm`
- `cargo`
- `docker`
- `wsl`

These external tools are not bundled with Sane Windows and remain subject to their respective upstream licenses.

## Related Documentation

- [Project Overview](README.md)
- [User Guide](docs/USER_GUIDE.md)
- [Developer Guide](docs/DEVELOPMENT.md)
- [Security Policy](SECURITY.md)
- [MIT License](LICENSE)
