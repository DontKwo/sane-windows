# Developer `uv` Installation Guide

> **For Everyday Users**: You do **not** need `uv`, Python, or any command-line tool to use Sane Windows. Download `SaneWindows-Windows.exe` directly from the [Download Table](../README.md#download).

Developers running repository lint checks (`claudemd_linter.py` and `link_checker.py`) use [Astral `uv`](https://docs.astral.sh/uv/) for deterministic Python tooling execution.

---

## Windows

Choose either the official standalone installer or a Windows package manager:

### Official Standalone Installer (PowerShell)

```powershell
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

### Package Managers (`winget` or `scoop`)

```powershell
winget install --id=astral-sh.uv -e
# or
scoop install main/uv
```

---

## macOS

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
# or
brew install uv
```

---

## Linux

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
# or
pipx install uv
```

---

## Verification & Updating (All Platforms)

Restart your terminal after installation so `PATH` reloads cleanly, then check:

```bash
uv --version
```

Always execute repository Python lint scripts using `--no-project` as documented in [Developer Guide](DEVELOPMENT.md).

---

## Related Documentation

- [Project Overview](../README.md)
- [Developer Guide](DEVELOPMENT.md)
- [Windows Installation Guide](INSTALLATION.md)
- [Security Policy](../SECURITY.md)
