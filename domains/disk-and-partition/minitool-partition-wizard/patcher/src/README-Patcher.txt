MiniTool Partition Wizard 13.9 Patcher
=====================================

Run MTPWPatcher.exe. Windows will ask for administrator rights.

It auto-detects:
C:\Program Files\MiniTool Partition Wizard 13\partitionwizard.dll

Buttons
-------
Check
  Shows the DLL size, SHA256 and the state of all four patch sites.

Apply 4 Patches
  Applies both desktop patches and both WinPE patches, then verifies them.
  Close MiniTool Partition Wizard before clicking this.

Restore Original
  Restores the pristine 13.9 DLL from:
  C:\ProgramData\MTPWPatcher\backup\partitionwizard.dll.orig
  If that backup is missing, it lets you select a pristine DLL.

Browse
  Select a different partitionwizard.dll.

Build lock
----------
This patcher accepts only the 13.9 DLL:
  size    8,432,880 bytes
  pristine SHA256 02ED32946FFA02F938107B9BFF233B1E063F38762A553BD209F698B4E07E650D
  patched  SHA256 8B4442B4F5816530AE6B3CBB842133FB246737AB57AF714F5267B59F55A093BA

It refuses unknown sizes or unknown bytes. Do not use it on a newer build
without re-checking the function offsets.

After patching
--------------
Rebuild the bootable media from the app so boot.wim contains the new DLL.
The old ISO keeps the old DLL.

Build from source
-----------------
No Python or SDK is needed, only the .NET Framework compiler that ships
with Windows:

  %WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo ^
    /target:winexe /platform:anycpu /optimize+ /langversion:5 ^
    /win32manifest:app.manifest /out:MTPWPatcher.exe ^
    /r:System.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll ^
    PatcherCore.cs MTPWPatcher.cs
