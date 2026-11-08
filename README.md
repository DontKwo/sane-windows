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

## Configuration Reference (`config.yaml`)

### 1. Privacy & Anti-Telemetry
* **`disable_telemetry`**: Sets diagnostic data to minimum security level.
* **`disable_advertising_id`**: Turns off advertising ID and diagnostic tracking across apps.
* **`disable_bing_search`**: Disables Bing web results in Start Menu search (local search only).
* **`disable_activity_history`**: Disables Timeline and user activity tracking.
* **`disable_feedback_prompts`**: Disables Windows feedback questionnaires.
* **`disable_telemetry_tasks`**: Disables diagnostic scheduled tasks in Task Scheduler.
* **`disable_suggested_actions`**: Disables Suggested Actions (clipboard tracking for dates/numbers).
* **`disable_diagtrack_service`**: Disables Connected User Experiences and Telemetry (DiagTrack) service.

### 2. File Explorer & Navigation
* **`show_file_extensions`**: Always shows file extensions in File Explorer.
* **`show_hidden_files`**: Always shows hidden files and folders.
* **`launch_to_this_pc`**: Opens File Explorer to "This PC" instead of "Home".
* **`show_full_path_in_title`**: Displays full directory path in Explorer title bars.
* **`show_seconds_in_clock`**: Displays seconds in taskbar system clock.
* **`add_open_with_code`**: Adds "Open with Code" context menu entries for folders, files, and drives.
* **`add_open_in_terminal`**: Adds "Open in Windows Terminal" context menu entries for folders and drives.
* **`enable_taskbar_end_task`**: Windows 11 (23H2+): Adds "End Task" to right-click menus on taskbar icons.
* **`disable_search_highlights`**: Removes web search illustrations and trending content from taskbar search.
* **`disable_store_app_prompt`**: Disables "Search the Microsoft Store" dialog when opening unknown files.
* **`disable_lock_screen_ads`**: Disables lock screen spotlights, trivia, and promotional tips.
* **`disable_snap_assist_popups`**: Disables Snap Assist suggestions and layout popups when snapping windows.
* **`disable_mouse_sticky_corners`**: Disables corner cursor friction for smooth multi-monitor mouse movement.

### 3. Startup Speed & System Performance
* **`disable_startup_delay`**: Removes the default Windows startup delay for desktop apps.
* **`disable_edge_background_tasks`**: Stops Microsoft Edge from pre-launching background processes.
* **`disable_fast_startup`**: Disables Fast Startup to prevent kernel state carryover across reboots.
* **`unlock_ultimate_performance`**: Unlocks the "Ultimate Performance" power plan.
* **`enable_hardware_gpu_scheduling`**: Enables Hardware Accelerated GPU Scheduling.

### 4. UI Cleanliness & De-bloat
* **`enable_dark_mode`**: Applies system-wide dark mode to Windows and applications.
* **`classic_context_menu`**: Windows 11: Restores Windows 10 right-click menu without "Show more options".
* **`left_align_taskbar`**: Windows 11: Moves taskbar icons from center to left.
* **`disable_aero_shake`**: Disables title bar shake minimizing other windows.
* **`hide_taskbar_copilot_button`**: Hides Copilot button from taskbar.
* **`hide_taskbar_task_view`**: Hides Task View button from taskbar.
* **`hide_taskbar_widgets`**: Hides Widgets button from taskbar.
* **`disable_widgets_hover`**: Disables Widgets board from opening on hover.
* **`disable_start_recommendations`**: Disables Recommended section in Start Menu.
* **`silence_tips_and_suggestions`**: Disables tips, suggestions, and promotional system notifications.
* **`remove_bloatware_apps`**: Removes pre-installed promotional AppX packages.
* **`bloatware_list`**: List of specific AppX package IDs targeted by `remove_bloatware_apps`.
* **`disable_sticky_keys_popup`**: Disables Sticky Keys, Toggle Keys, and Filter Keys shortcut popups.

### 5. Developer & Terminal Ergonomics
* **`enable_developer_mode`**: Enables Windows Developer Mode.
* **`enable_long_paths`**: Enables Win32 long paths (>260 characters).
* **`configure_git_autocrlf`**: Sets `git config --global core.autocrlf true`.
* **`enable_powershell_shortcuts`**: Adds aliases (`which`, `ll`) and PSReadLine prediction autocomplete to PowerShell profiles.
* **`enable_terminal_duplicate_tab`**: Configures Windows Terminal and PowerShell prompt integration (OSC 9;9) so `Ctrl + Shift + D` opens duplicate tabs in the current working directory.
* **`require_ctrl_shift_copy_paste`**: Binds `Ctrl + Shift + C` and `Ctrl + Shift + V` for copy/paste in Terminal and PSReadLine, keeping `Ctrl + C` reserved for SIGINT.

### 6. Windows Update Control
* **`no_auto_restart_logged_on`**: Blocks automatic restarts for updates when a user is logged in.
* **`exclude_drivers`**: Prevents Windows Update from installing hardware driver updates.

---

## Safety & Compatibility Guards

* **OS Platform Guard**: Halts immediately on non-Windows platforms without modifying system state.
* **Version Isolation**:
  * Windows 11 features (`classic_context_menu`, `hide_taskbar_copilot_button`, `hide_taskbar_widgets`) skip automatically on Windows 10.
  * Windows 11 23H2+ features (`enable_taskbar_end_task`, Build $\ge 22631$) skip on earlier builds.
* **Idempotent Checks**: Reads current values before modification. Settings matching desired state are marked `[UNCHANGED]` and skipped.
* **Automatic Snapshots & Rollback**: Saves timestamped JSON snapshots to `snapshots\` before changes occur. Run `.\setup.ps1 -Revert` to restore registry values, PowerShell profiles, and git settings.
