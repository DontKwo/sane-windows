# Sane Windows - AI Agent Operational Reference

## Technical Architecture

Sane Windows combines core PowerShell automation scripts with a WebView desktop interface (`SaneWindows-Windows.exe`) compiled from `scripts/SaneWindowsHost.cs` and `gui/`:

- **`setup.ps1`**: Validates Windows platform, reads `config.yaml`, previews planned Registry/system changes with `-WhatIf`, saves rollback snapshots under `snapshots/`, applies changes, and restores state with `-Revert`.
- **`clean-storage.ps1`**: Scans user/dev/browser caches (`uv`, `pip`, `npm`, `pnpm`, `yarn`, Cargo, Gradle, Go, NuGet, Docker/WSL), exports JSON audits with `-ExportJson`, and cleans with confirmation.
- **`check-tooling.ps1`**: Audits installed developer CLIs (`git`, `uv`, `python`, `pnpm`, `npm`, `cargo`, `docker`, `wsl`) and installs/updates on explicit user action.
- **`scripts/SaneWindowsHost.cs` + `gui/`**: Loopback HTTP desktop host serving the HTML/CSS/JS UI, exposing `/api/config`, `/api/setup/*`, `/api/cleanup/*`, `/api/tooling/*`, and `--self-test`.

## Rules & Constraints

- **OS Guard**: Registry tweaks and cleanup actions require Windows (`Win32NT`); Pester unit logic parses AST-safe helper functions cross-platform where needed.
- **Safety Gate**: Destructive or system-modifying calls from the GUI always trigger an explicit confirmation dialog before invoking `-Yes`, `-Revert`, or `-Install`.
- **No Secrets**: Never commit tokens, credentials, snapshots, or personal paths (`Rule 91`).
- **Tests**: Run Pester tests (`Invoke-Pester -Path ./*.Tests.ps1`) and executable `--self-test` before committing.

## Related Documentation

- [Project Overview](README.md)
- [User Guide](docs/USER_GUIDE.md)
- [Customization Reference](docs/CUSTOMIZATION.md)
- [Developer Guide](docs/DEVELOPMENT.md)
- [Security Policy](SECURITY.md)
