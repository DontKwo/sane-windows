# Sane Windows - FAQ

## Common Questions

### Does this break Windows Updates?
No. The `windows_update` section of `config.yaml` provides controls like `no_auto_restart_logged_on` and `exclude_drivers`. However, it does not stop Windows from receiving security patches or general updates.

### Will this trigger anti-cheat software in games?
The configurations applied by Sane Windows are standard OS features, registry changes, and privacy toggles. They do not inject into game processes, bypass kernel protections, or behave like cheats. Anti-cheat software should remain unaffected.

### How do I reverse the tweaks?
`setup.ps1` creates an automatic snapshot before making any changes. To restore your system settings, simply run:
```powershell
.\setup.ps1 -Revert
```
This will restore your registry keys, PowerShell profiles, Git settings, and context menus to their pre-execution state.

### What if I don't want a specific tweak?
You can disable any tweak by setting its corresponding value to `false` in your `config.yaml` file. The scripts are entirely modular.

### My changes didn't apply. What should I do?
1. Check the console output to ensure the change was actually applied (and not marked `[UNCHANGED]` or `[SKIPPED]`).
2. Some changes require Administrator privileges. Run `.\setup.ps1 -Elevate`.
3. Certain UI tweaks require a File Explorer restart or a system reboot to take full effect.
