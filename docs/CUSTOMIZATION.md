# Sane Windows - Customization Reference

## Configuration Reference (`config.yaml`)

This section maps out the structure of the `config.yaml` file that drives `setup.ps1`.

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

## Extending with Custom Presets

You can export your current machine configuration to create a custom preset YAML file.

```powershell
.\setup.ps1 -ExportConfig -ExportPath path\to\my_preset.yaml
```

You can then apply your preset directly:
```powershell
.\setup.ps1 -ConfigPath path\to\my_preset.yaml
```
