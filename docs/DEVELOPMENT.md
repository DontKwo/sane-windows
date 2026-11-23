# Developer Guide

Develop, test, lint, and package Sane Windows on Windows 10 / 11.

## Prerequisites

- **PowerShell 7+ (`pwsh`)** and **Pester 5+** (`Install-Module -Name Pester -Force`)
- **.NET Framework 4.x (`csc.exe`)** included on Windows for compiling `SaneWindows-Windows.exe`
- **Python 3.12+** and [`uv`](UV_INSTALLATION.md) for strict repository linting and link checks

---

### Windows

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path ./*.Tests.ps1 -CI"
pwsh -NoProfile -File .\setup.ps1 -WhatIf
pwsh -NoProfile -File .\clean-storage.ps1 -WhatIf
pwsh -NoProfile -File .\scripts\build_desktop_exe.ps1
.\build\SaneWindows-Windows.exe --self-test
```

---

## Verification & Linting

Run Pester tests, desktop host verification, strict linter, and markdown link checks before opening a pull request:

```powershell
uv run --no-project python ../ai-dev-tools/scripts/claudemd_linter.py . --level strict --full
uv run --no-project python ../ai-dev-tools/scripts/link_checker.py .
```

---

## Related Documentation

- [Project Overview](../README.md)
- [User Guide](USER_GUIDE.md)
- [Customization Reference](CUSTOMIZATION.md)
- [Windows Installation Guide](INSTALLATION.md)
- [Developer uv Installation](UV_INSTALLATION.md)
- [AI Agent Rules](../AGENTS.md)
- [Security Policy](../SECURITY.md)
