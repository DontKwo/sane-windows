# Useful Setup: Windows QOL, Privacy, Performance & Ergonomics

A modular, snapshot-backed setup script designed for any Windows 10/11 machine. Configure your desired system settings in a simple YAML file, run `setup.bat`, and your machine is configured in seconds.

---

## The Workflow

```
           +-------------+
           | config.yaml |  <-- Edit your preferences (true/false)
           +------+------+
                  |
                  v
           +-------------+
           |  setup.bat  |  <-- Double-click to run
           +------+------+
                  |
                  v
     [Planned Changes Preview]   <-- Displays a table of planned diffs
                  |
       Ask user to confirm? [Y/n]
       ├── [n] -> Aborts cleanly (no changes made)
       └── [Y] -> Takes safety snapshot & applies changes
```

---

## Quick Start

### 1. Apply Settings
Double-click `setup.bat` (or run in PowerShell):
```powershell
.\setup.ps1
```
* If all settings match: Reports `0 changes needed` and exits.
* If settings need updating: Pretty-prints the preview table and asks for confirmation (`[Y/n]`).
* *(To run unattended without prompt, pass `-Yes`: `.\setup.ps1 -Yes`)*

### 2. Preview Without Changing (Dry Run)
Preview planned diffs without modifying anything or prompting:
```powershell
.\setup.ps1 -WhatIf
```

### 3. Export Machine Configuration to YAML
Inspect the current machine's settings and generate a ready-to-use YAML configuration:
```powershell
.\setup.ps1 -ExportConfig
```
*(Optionally specify a custom output path with `-ExportPath path\to\my_config.yaml`)*

### 4. Revert / Rollback Anytime
To revert your system back to the snapshot taken before the last run:
```powershell
.\setup.ps1 -Revert
```
*(Or in cmd: `setup.bat -Revert`)*

To view all saved snapshots:
```powershell
.\setup.ps1 -ListSnapshots
```

---

## What It Configures (`config.yaml`)

### 1. Privacy & Anti-Telemetry
* **`disable_telemetry`**: Restricts diagnostic telemetry to minimum security level.
* **`disable_advertising_id`**: Disables advertising ID and personalized diagnostic data tracking.
* **`disable_bing_search`**: Turns off Bing web search in the Start Menu (pure local app/file search).
* **`disable_activity_history`**: Disables timeline feed and user activity syncing.
* **`disable_feedback_prompts`**: Stops Windows feedback popup questionnaires.
* **`disable_telemetry_tasks`**: Disables background telemetry and diagnostic scheduled tasks in Task Scheduler.

### 2. File Explorer & Navigation
* **`show_file_extensions`**: Always shows file extensions (`.py`, `.exe`, `.json`, etc.).
* **`show_hidden_files`**: Always displays hidden files and folders (`AppData`, `.git`, etc.).
* **`launch_to_this_pc`**: Opens File Explorer directly to "This PC" instead of "Home".
* **`classic_context_menu`**: Windows 11: Restores the instant classic Windows 10 right-click menu (no "Show more options").
* **`show_full_path_in_title`**: Displays the full folder path in Explorer title bars.
* **`show_seconds_in_clock`**: Displays seconds in the taskbar system clock.
* **`add_open_with_code`**: Adds "Open with Code" to right-click context menus for folders, empty folder background, files, and drives.
* **`add_open_in_terminal`**: Adds "Open in Windows Terminal" to right-click context menus for folders, folder backgrounds, and drives.
* **`enable_taskbar_end_task`**: Windows 11 (23H2+): Adds "End Task" directly to taskbar app icon right-click menus to kill frozen apps immediately.
* **`disable_search_highlights`**: Removes Bing web search doodles, trending topics, and cartoons from the taskbar search box.
* **`disable_store_app_prompt`**: Prevents the "Look for an app in the Microsoft Store" popup when opening unknown file types (goes straight to local Open With).
* **`disable_lock_screen_ads`**: Turns off lock screen rotating spotlights, trivia overlays, tips, and promotional ads.
* **`disable_snap_assist_popups`**: Turns off window Snap Assist thumbnail popups and flyouts when snapping windows.
* **`disable_mouse_sticky_corners`**: Disables cursor sticking at multi-monitor boundary corners for seamless mouse transitions between displays.

### 3. Startup Speed & System Performance
* **`disable_startup_delay`**: Removes the artificial Windows startup delay for desktop apps.
* **`disable_edge_background_tasks`**: Stops Microsoft Edge from pre-launching and idling in the background.
* **`disable_fast_startup`**: Disables Fast Startup (avoids hibernation kernel corruption across reboots).
* **`unlock_ultimate_performance`**: Unlocks the hidden Windows "Ultimate Performance" power plan to minimize hardware micro-stutters and latency.

### 4. UI Cleanliness & De-bloat
* **`hide_taskbar_copilot_button`**: Hides the Copilot button from the taskbar.
* **`hide_taskbar_task_view`**: Hides the Task View (virtual desktops) button.
* **`hide_taskbar_widgets`**: Hides the Widgets / Weather board from the taskbar.
* **`silence_tips_and_suggestions`**: Silences suggested content, tips, and Windows promo notifications.
* **`disable_sticky_keys_popup`**: Disables Sticky Keys, Toggle Keys, and Filter Keys shortcut dialogs (5x Shift, 5s NumLock, 8s Right Shift).
* **`remove_bloatware_apps`**: Removes pre-installed promotional junk apps (TikTok, Disney+, Solitaire, News, Weather, Skype, Clipchamp, etc.).

### 5. Developer & Terminal Ergonomics
* **`enable_long_paths`**: Enables Win32 Long Paths (>260 character paths).
* **`configure_git_autocrlf`**: Configures `git config --global core.autocrlf true`.
* **`enable_powershell_shortcuts`**: Adds aliases (`which`, `ll`) and `PSReadLine` history prediction autocompletion to PowerShell profiles.
* **`enable_terminal_duplicate_tab`**: Configures Windows Terminal and PowerShell prompt integration (OSC 9;9) so **`Ctrl + Shift + D`** (or right-click $\rightarrow$ Duplicate Tab) opens a new tab in the **exact same directory**.
* **`require_ctrl_shift_copy_paste`**: Configures Windows Terminal and PowerShell (`PSReadLine`) so you must use **`Ctrl + Shift + C`** and **`Ctrl + Shift + V`** to copy/paste, freeing plain `Ctrl + C` strictly for interrupt (`SIGINT`) and eliminating accidental pastes.

### 6. Windows Update Control
* **`no_auto_restart_logged_on`**: Prevents Windows from automatically restarting for updates while an active user is logged in.
* **`exclude_drivers`**: Excludes third-party driver updates from routine Windows Updates (prevents GPU and peripheral drivers from being unexpectedly overwritten).

---

## Safety & Compatibility Guards

* **OS Platform Guard**: Automatically detects non-Windows platforms (e.g. running from Linux or macOS via PowerShell Core) and immediately halts with a clear error without modifying anything.
* **Version Isolation**:
  * Windows 11-only features (such as `classic_context_menu`, `hide_taskbar_copilot_button`, and `hide_taskbar_widgets`) are automatically skipped when run on Windows 10.
  * Windows 11 23H2+ features (such as `enable_taskbar_end_task`, which requires Build $\ge 22631$) are automatically skipped on earlier builds.
* **Zero-Touch When Already Set**: Every setting is checked before applying. If a setting already has the desired value, it is reported as `[UNCHANGED]` and left alone.
* **Automatic Snapshots**: A timestamped JSON snapshot of your system state is saved in `snapshots\` before any change is made.
* **Full Rollback**: Running `.\setup.ps1 -Revert` reads the snapshot and restores original registry values, PowerShell profiles, and git configurations.

