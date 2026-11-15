UltraISO Premium 9.7.6.3829 patcher
===================================

A single PowerShell script. It does not download anything, does not phone home,
and does not carry a prebuilt binary.

Requirements
  Windows PowerShell 5.1 or PowerShell 7.
  The shipped UltraISO Premium 9.7.6.3829 executable (5543368 bytes,
  sha256 F89E9D336C6F49FBD847EA513A11BB1BFA80EA5FD1336E23CAD7D80370BAEA65).

Build
  powershell -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
  The script is parse-checked and copied to dist\patch-ultraiso.ps1.
  dist\ is a local artifact and is not committed.

Run
  Check    powershell -NoProfile -ExecutionPolicy Bypass -File .\dist\patch-ultraiso.ps1 -Mode Check
  Apply    powershell -NoProfile -ExecutionPolicy Bypass -File .\dist\patch-ultraiso.ps1 -Mode Apply
  Restore  powershell -NoProfile -ExecutionPolicy Bypass -File .\dist\patch-ultraiso.ps1 -Mode Restore

Target selection
  Without -Target the patcher reads the install folder from
  HKCU\SOFTWARE\EasyBoot Systems\UltraISO\5.0 and falls back to
  %ProgramFiles(x86)%\UltraISO\UltraISO.exe. Pass -Target to work on a copy:

    .\dist\patch-ultraiso.ps1 -Mode Apply -Target D:\lab\UltraISO.exe -BackupDir D:\lab\backup

Backup
  The pristine file is written to -BackupDir, default
  %ProgramData%\ultraiso-patch\backup\UltraISO.exe.orig. It is never written
  inside the install directory. Restore requires that backup and checks its
  hash before writing.

Safety
  Refuses any size other than 5543368.
  Refuses any byte state that is neither pristine nor already patched.
  Refuses to write while UltraISO.exe is running.
  Writes a temp file, verifies its hash, then replaces the target atomically.
  Re-verifies the hash after the swap.
  Restores the original file attributes, including read-only.
  Apply is idempotent: a second run reports already patched and writes nothing.
  Elevates through a UAC prompt when the install directory needs it; use
  -NoElevate to fail instead of prompting.

Exit codes
  0 success, already patched, or already pristine
  1 unsupported build (Check) or any refusal (throw)

Notes
  The patched file keeps the original Authenticode blob but its hash no longer
  matches, so the signature reports HashMismatch. Windows loads it unless Smart
  App Control is enforcing. See ..\playbook.md for the full analysis.
