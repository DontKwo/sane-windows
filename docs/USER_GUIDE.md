# Sane Windows - User Guide

## Introduction

Sane Windows provides two primary scripts designed to improve your Windows experience safely:
1.  **`setup.ps1`**: Reads `config.yaml` to configure privacy, Explorer, UI debloat, and more.
2.  **`clean-storage.ps1`**: Reclaims disk space by clearing various caches.

## Running the Setup Script

To apply configurations, edit `config.yaml` as required, then run:

```powershell
.\setup.ps1
```

By default, the script will show you a table of planned changes and prompt for confirmation.

### Execution Modes

*   **Dry Run**: To preview the changes without modifying the system, run `.\setup.ps1 -WhatIf`.
*   **Unattended Mode**: To skip all confirmation prompts, run `.\setup.ps1 -Yes`.
*   **Interactive Mode**: To be prompted for each individual change, select `I` when prompted during standard execution.

### Administrator Privileges

Some changes (like telemetry tasks or long path support) require Administrator privileges. If you are not running as Admin, you can self-elevate by using:
```powershell
.\setup.ps1 -Elevate
```

## Running the Storage Cleaner

To scan and clean system caches and build artifacts:

```powershell
.\clean-storage.ps1
```

### Options

*   **Dry Run**: See what would be deleted: `.\clean-storage.ps1 -WhatIf`
*   **Unattended**: Clean all without prompting: `.\clean-storage.ps1 -Yes`
*   **Interactive**: Confirm each cleanup target: `.\clean-storage.ps1 -Interactive`
*   **Preserve Recent**: Keep files modified within the last N days (e.g., 7 days): `.\clean-storage.ps1 -MinAgeDays 7`

## Rollbacks and Snapshots

`setup.ps1` takes an automatic snapshot of your settings before it makes any modifications.

### Viewing Snapshots

To list available snapshots:
```powershell
.\setup.ps1 -ListSnapshots
```

### Reverting Changes

To revert your system to a previous state:
```powershell
.\setup.ps1 -Revert
```
*You can also specify a specific snapshot using `-SnapshotPath path\to\snapshot.json`.*

## Important Considerations

*   **Disclaimer**: This software makes low-level Windows configuration changes. Run at your own risk.
*   **Explorer Restarts**: Some changes to the UI or Taskbar require File Explorer to restart to take effect. The script will safely handle this.
