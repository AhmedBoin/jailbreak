@echo off
setlocal
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
"%CSC%" /nologo /target:winexe /platform:anycpu /optimize+ /langversion:5 /win32manifest:app.manifest /out:MTPWPatcher.exe /r:System.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll PatcherCore.cs MTPWPatcher.cs
exit /b %errorlevel%
