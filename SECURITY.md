# Security Policy

## Supported Versions
Only the `main` branch is actively supported with security updates. We do not backport fixes to older releases.

## Reporting a Vulnerability
To report a vulnerability, please do NOT open a public issue. Instead, contact the repository owner privately.

## Safe Defaults
- Scripts should NEVER hardcode, print, paste, log, or commit secret values, passwords, tokens, API keys, or email addresses.
- Scripts must not use `Invoke-Expression` for executing dynamic commands; prefer `& ([scriptblock]::Create(...))` or direct parameter binding.
- Always use manual inner quotes for paths containing spaces when passing them to `Start-Process` via `-ArgumentList` to ensure they are parsed correctly by the target executable.
- Use `New-TemporaryFile` to generate temporary files predictably and safely during testing or execution.
- Maintain anonymity and refrain from logging user-specific paths or handles in code or metadata.
