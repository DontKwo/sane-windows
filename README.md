# Sane Windows

Modular system configuration and disk maintenance for Windows 10 and 11.

---

## Overview

SYSTEM MODIFICATION DISCLAIMER: sane-windows scripts execute low-level Windows configuration changes, registry edits, service adjustments, and environment modifications. Run at your own risk. The software is provided AS IS, without warranty of any kind. The author is not liable for system instability, data loss, operating system recovery requirements, or policy violations.

Sane Windows provides two snapshot-safe management tools:
* **`setup.ps1`**: Configures privacy, Explorer, performance, UI, developer ergonomics, and Windows Update settings defined in `config.yaml`. Takes an automatic snapshot before making modifications to allow immediate rollback.
* **`clean-storage.ps1`**: Reclaims disk space by clearing temporary files, package caches (`uv`, `pip`, `npm`, `pnpm`, `yarn`), compiler toolchains, application caches, crash dumps, and container runtimes with explicit confirmation prompts.

---

## Quick Start

### 1. System Configuration

Edit preferences in `config.yaml`, then run:
```powershell
.\setup.ps1
```

* **Preview diffs (dry run):**
  ```powershell
  .\setup.ps1 -WhatIf
  ```
* **Run unattended (skip confirmation prompts):**
  ```powershell
  .\setup.ps1 -Yes
  ```
* **Request Administrator privileges (self-elevation via UAC):**
  ```powershell
  .\setup.ps1 -Elevate
  ```
* **Export current machine settings to YAML:**
  ```powershell
  .\setup.ps1 -ExportConfig [-ExportPath path\to\config.yaml]
  ```
* **Restore previous settings (rollback):**
  ```powershell
  .\setup.ps1 -Revert [-SnapshotPath path\to\snapshot.json]
  ```
* **List available snapshots:**
  ```powershell
  .\setup.ps1 -ListSnapshots
  ```
* **Compare two snapshots:**
  ```powershell
  # Requires dot-sourcing or loading the function from setup.ps1
  . .\setup.ps1
  Compare-SystemSnapshots -SnapshotA snapshots\old.json -SnapshotB snapshots\new.json
  ```
* **Additional flags:**
  * `-ConfigPath <path>`: Load a custom YAML configuration.
  * `-NoExplorerRestart`: Skip restarting File Explorer after Explorer/Taskbar tweaks.
  * `-VerboseOutput`: Display unchanged settings alongside planned modifications.

When running interactively, `setup.ps1` presents a planned changes table and prompts:
* `[Y] Yes`: Create a snapshot and apply all changes.
* `[N] No`: Abort without applying changes.
* `[I] Individual`: Prompt for each change individually.

---

### 2. Disk & Cache Cleanup

Scan and clean system caches and build artifacts:
```powershell
.\clean-storage.ps1
```

* **Preview cleanable items without deleting (dry run):**
  ```powershell
  .\clean-storage.ps1 -WhatIf
  ```
* **Clean all detected items automatically:**
  ```powershell
  .\clean-storage.ps1 -Yes
  ```
* **Confirm each cleanup item individually:**
  ```powershell
  .\clean-storage.ps1 -Interactive
  ```
* **Audit disk space and output JSON report:**
  ```powershell
  .\clean-storage.ps1 -ExportJson
  ```
* **Audit disk space and save JSON report to file:**
  ```powershell
  .\clean-storage.ps1 -ExportJson -ExportPath path\to\audit.json
* **Preserve recent files (e.g., modified within the last 7 days):**
  ```powershell
  .\clean-storage.ps1 -MinAgeDays 7
  ```

Cleaned targets include:
* User temporary files (`%TEMP%`)
* Command history: PowerShell `PSReadLine` history
* Browser caches: Chrome, Edge, Firefox
* Package caches: `uv`, `pip`, `npm`, `pnpm`, `yarn`, Cargo (`cargo`), Gradle, Go, NuGet, `vcpkg`
* Toolchains and models: Rust nightly (`rustup`), Visual Studio Installer, MSBuild, `rembg` ONNX models
* Application caches and superseded builds: VS Code staged VSIX packages, VS Code stale workspace storage (`workspaceStorage`), Raspberry Pi Imager OS cache, superseded Claude Desktop and MathWorks ServiceHost installations, Claude project workflows
* Windows Update download cache: Downloaded installation payloads (requires admin)
* Diagnostic data: Windows error crash dumps and minidumps (`.dmp`), Autodesk CER reports
* Container and VM runtimes: Docker prune (`docker system prune -a --volumes -f`), WSL2 VM shutdown (`wsl --shutdown`)

---

### 3. Tooling Diagnostics & Auto Install / Update

Diagnose installed developer CLIs and versions:
```powershell
.\check-tooling.ps1
```

* **Automatically install missing developer tools:**
  ```powershell
  .\check-tooling.ps1 -Install
  ```
* **Update installed developer tools:**
  ```powershell
  .\check-tooling.ps1 -Update
  ```
* **Install or update specific tools only:**
  ```powershell
  .\check-tooling.ps1 -Install -Tool uv, git
  .\check-tooling.ps1 -Update -Tool pnpm
  ```

Supported CLIs include: `git`, `uv`, `python`, `pnpm`, `npm`, `cargo`, `docker`, and `wsl`.

---

## Documentation

For full details, please refer to the documentation:

*   **[User Guide](docs/USER_GUIDE.md)**: Step-by-step instructions on running the scripts safely.
*   **[Customization Reference](docs/CUSTOMIZATION.md)**: Complete map of `config.yaml` and guide for custom presets.
*   **[FAQ](docs/FAQ.md)**: Common questions about Windows updates, anti-cheat, rollbacks, and troubleshooting.

---

## Safety & Compatibility Guards

* **OS Platform Guard**: Halts immediately on non-Windows platforms without modifying system state.
* **Version Isolation**:
  * Windows 11 features (`classic_context_menu`, `hide_taskbar_copilot_button`, `hide_taskbar_widgets`) skip automatically on Windows 10.
  * Windows 11 23H2+ features (`enable_taskbar_end_task`, Build $\ge 22631$) skip on earlier builds.
* **Idempotent Checks**: Reads current values before modification. Settings matching desired state are marked `[UNCHANGED]` and skipped.
* **Automatic Snapshots & Rollback**: Saves timestamped JSON snapshots to `snapshots\` before changes occur. Run `.\setup.ps1 -Revert` to restore registry values, PowerShell profiles, and git settings.
