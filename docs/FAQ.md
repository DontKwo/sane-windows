# Sane Windows - Frequently Asked Questions

## General Safety & Recovery

### How do I undo tweaks applied by Sane Windows?
`setup.ps1` automatically writes a snapshot file under `snapshots\` before changing any setting. Open the **System Tweaks** tab and click **Revert Snapshot**, or run `.\setup.ps1 -Revert` from PowerShell.

### Does this break Windows Updates?
No. The `windows_update` options (`no_auto_restart_logged_on` and `exclude_drivers`) prevent sudden reboots while signed in and optional driver pushes, while leaving standard security updates enabled.

### Will this trigger anti-cheat software in games?
Sane Windows adjusts standard OS registry settings, Explorer preferences, and telemetry policies without kernel hooks or process injection.

## Troubleshooting

### Why did Windows SmartScreen warn when opening the `.exe`?
Independently published executables without commercial EV certificates trigger Microsoft Defender SmartScreen on first launch. Verify the download came from [DontKwo/sane-windows Releases](https://github.com/DontKwo/sane-windows/releases/latest) and follow [Windows Installation Guide](INSTALLATION.md).

### Why didn't a specific tweak apply?
1. Confirm the toggle is `true` in `config.yaml` and saved before applying.
2. Some HKLM policies and Win32 long-path keys require Administrator privileges. Run the app or `.\setup.ps1 -Elevate` as Administrator.
3. Explorer and taskbar visual tweaks require File Explorer restart or sign-out/reboot.

## Related Documentation

- [Project Overview](../README.md)
- [User Guide](USER_GUIDE.md)
- [Windows Installation Guide](INSTALLATION.md)
- [Customization Reference](CUSTOMIZATION.md)
- [Developer Guide](DEVELOPMENT.md)
- [Security Policy](../SECURITY.md)
