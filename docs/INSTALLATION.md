# Windows Installation Guide

Install and run Sane Windows without manually cloning scripts or running PowerShell commands.

## Safety & Authenticity Warning

- **Official `main` Releases Only**: Download Sane Windows exclusively from [DontKwo/sane-windows Releases](https://github.com/DontKwo/sane-windows/releases/latest).
- **Fork Warning**: Never download builds from forked repositories unless you have verified the source code yourself and know they do not contain malware. Only official `main` releases are maintained by the author, and I make no promises.
- **Bypassing Security Prompts**: Because independent open-source executables do not carry paid commercial signing certificates, Windows will warn that the app is unrecognized or potentially unsafe. Bypassing these warnings is strictly at your own discretion, and the software is provided "AS IS" with zero liability.
- **System Modifications**: Applying registry tweaks or clearing system caches modifies Windows configuration on your device. Preview changes first and use at your own risk.

---

## Windows

1. Download `SaneWindows-Windows.exe` from [Latest Releases](https://github.com/DontKwo/sane-windows/releases/latest).
2. Place `SaneWindows-Windows.exe` alongside your preferred `config.yaml` folder (or launch it anywhere to generate/edit your active workspace configuration).
3. Double-click `SaneWindows-Windows.exe` to open the desktop window.
4. If **Microsoft Defender SmartScreen** displays *"Windows protected your PC"*:
   - Click **More info**.
   - Confirm the download source is `DontKwo/sane-windows`, then click **Run anyway** at your own discretion.
5. Alternative unblock method: Right-click `SaneWindows-Windows.exe` -> **Properties** -> check **Unblock** near the bottom under Security -> click **Apply** and **OK** -> open the file normally.

> Note: Sane Windows targets Windows 10 and Windows 11 exclusively (`Win32NT`). macOS and Linux are not supported.

---

## Related Documentation

- [Project Overview](../README.md)
- [User Guide](USER_GUIDE.md)
- [Customization Reference](CUSTOMIZATION.md)
- [Frequently Asked Questions](FAQ.md)
- [Developer Guide](DEVELOPMENT.md)
- [Security Policy](../SECURITY.md)
- [MIT License](../LICENSE)
