# Security Policy

## Supported Versions & Official Releases

| Version / Branch | Supported | Notes |
| :--- | :--- | :--- |
| `main` (Latest `vX.Y.Z` Release) | Yes | Actively maintained official release stream |
| Forks, Mirrors, and Older Tags | No | Unverified and unsupported |

Official executables are distributed exclusively from the primary `DontKwo/sane-windows` repository on GitHub (`main` branch and official [Releases](https://github.com/DontKwo/sane-windows/releases/latest)).

- **Fork Safety Warning**: Do **not** download or run installers or executables from forked repositories or third-party mirrors unless you have verified the source code yourself and confirmed they contain no malware. Only `DontKwo/sane-windows` `main` builds are maintained by the author.
- **OS Security Prompts**: Because Sane Windows is published independently without paid commercial code-signing certificates, Windows SmartScreen will warn that `SaneWindows-Windows.exe` is unrecognized or potentially unsafe. Review [Windows Installation Guide](docs/INSTALLATION.md) and bypass security prompts strictly at your own discretion.

## Warranty & Liability Disclaimer

Sane Windows executes Windows Registry edits, service adjustments, cache cleanup, and developer tool installs. It is provided "AS IS" under the [MIT License](LICENSE), without warranty of any kind, express or implied. The author assumes zero responsibility or liability for system instability, registry modifications, data loss, or damages arising from running this software. Always review `-WhatIf` previews and keep snapshots. You use this software entirely at your own risk and discretion.

## Safe Engineering Rules

- Never hardcode or log secret values, tokens, API keys, or personal paths.
- Never use `Invoke-Expression` on dynamic external strings; bind parameters directly.
- Always quote filesystem paths and use `New-TemporaryFile` for temporary scratch data.

## Reporting a Vulnerability

If you discover a security issue in `DontKwo/sane-windows`:

1. **Do not** disclose exploit details or credentials in a public GitHub Issue.
2. Open a [Private Vulnerability Report](https://github.com/DontKwo/sane-windows/security/advisories/new) on GitHub (or contact `@DontKwo` via GitHub profile).
3. Include reproduction steps, Windows build version, and any suggested fix.

## Related Documentation

- [Project Overview](README.md)
- [User Guide](docs/USER_GUIDE.md)
- [Windows Installation Guide](docs/INSTALLATION.md)
- [Customization Reference](docs/CUSTOMIZATION.md)
- [Developer Guide](docs/DEVELOPMENT.md)
- [License](LICENSE)
