# Sane Windows - User Guide

Sane Windows helps you configure Windows 10 and Windows 11 privacy, File Explorer, taskbar layout, developer settings, cache cleanup, and CLI tooling from one graphical desktop app (`SaneWindows-Windows.exe`) or from PowerShell.

## Desktop Application Workflow

1. Launch `SaneWindows-Windows.exe` (see [Windows Installation Guide](INSTALLATION.md) if Microsoft Defender SmartScreen prompts).
2. **System Tweaks tab**: Review switches loaded from `config.yaml`, click **Preview Diffs (-WhatIf)** for a safe dry-run table, then click **Snapshot & Apply** to save an automatic backup and apply your selections.
3. **Rollback**: Select any timestamped snapshot in **System Tweaks** and click **Revert Snapshot** to restore previous registry and profile settings.
4. **Disk Cleanup tab**: Click **Scan Caches** to calculate reclaimable space, set an optional **Min Age (Days)** threshold, and click **Clean Selected** after reviewing the confirmation prompt.
5. **Tooling Check tab**: Audit installed developer tools (`git`, `uv`, `python`, `pnpm`, `npm`, `cargo`, `docker`, `wsl`) and trigger single-click installs or updates.

## PowerShell CLI Equivalent

Advanced users who run scripts directly from the repository root can use:

- **Dry-run preview**: `.\setup.ps1 -WhatIf`
- **Snapshot and apply**: `.\setup.ps1` (or `.\setup.ps1 -Yes`)
- **Rollback**: `.\setup.ps1 -Revert`
- **Storage audit / clean**: `.\clean-storage.ps1 -WhatIf` / `.\clean-storage.ps1`
- **Tooling diagnostics**: `.\check-tooling.ps1`

## Related Documentation

- [Project Overview](../README.md)
- [Windows Installation Guide](INSTALLATION.md)
- [Customization Reference](CUSTOMIZATION.md)
- [Frequently Asked Questions](FAQ.md)
- [Developer Guide](DEVELOPMENT.md)
- [Security Policy](../SECURITY.md)
