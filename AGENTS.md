# Sane Windows - AI Agent Operational Reference

## Technical Architecture

This repository contains PowerShell scripts meant for configuring a Windows machine.

### Script Execution Order & Structure

*   **`setup.ps1`**: The main configuration script. It relies heavily on `config.yaml`.
    *   **Execution Flow**:
        1.  Validates OS platform (halts on non-Windows).
        2.  Reads and validates `config.yaml` using internal `ConvertFrom-SimpleYaml` and `Test-ConfigFile`.
        3.  Determines administrative privileges via `Test-IsAdmin`.
        4.  Analyzes current system state against `config.yaml` to identify planned changes.
        5.  Prompts user for confirmation (unless `-Yes` is provided).
        6.  Takes a snapshot of current system state.
        7.  Applies changes via `Check-RegChange` and other functions.
        8.  Restarts Explorer if necessary.
*   **`clean-storage.ps1`**: The script for removing caches, artifacts and temporary files.
    *   Targets are mapped as `[PSCustomObject]` instances.
*   **`check-tooling.ps1`**: CLI tool diagnostic and updater.

### PowerShell Module Structure & Safety Checks

*   Scripts do **not** use batch files, relying entirely on PowerShell (`.ps1`).
*   **OS Guard**: Strict checking for Windows environment.
*   **Registry Safety Checks**: Operations modifying restricted paths (`HKLM:\`, `ServiceProfiles`, etc.) must be gated behind `Test-IsAdmin`.
*   **Rollback Logic (`setup.ps1`)**:
    *   Before applying changes, a snapshot is saved using `Save-Snapshot`.
    *   Users can revert changes by invoking `setup.ps1 -Revert`, which reads the snapshot and restores `HKCU` / `HKLM` registry paths, Git configs, Context Menu, and Terminal keys.

## Automated Verification & Testing

*   **Pester**: The project uses Pester (v5+ syntax). Run tests via: `pwsh -c 'Invoke-Pester *.Tests.ps1'`.
*   **Linting**: Static analysis using PSScriptAnalyzer is recommended: `pwsh -Command "Invoke-ScriptAnalyzer -Path .\setup.ps1"`.
*   **Linux Sandbox Testing**: The test environments typically run on Linux. To validate PowerShell syntax locally, use the AST parser instead of invoking scripts directly.

## Rules & Constraints

*   NEVER commit secrets, tokens, or personal identifiers.
*   The `config.yaml` drives `setup.ps1` behaviour.
*   Always use explicit, strict typing.
