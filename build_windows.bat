@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "UFO50_SOURCE=%~1"
if "%UFO50_SOURCE%"=="" set "UFO50_SOURCE=%~dp0ufo50"
if not "%UFO50_SOURCE:~-1%"=="\" set "UFO50_SOURCE=%UFO50_SOURCE%\"

set "WRAPPER_APK=%UFO50_WRAPPER_APK%"
if "%WRAPPER_APK%"=="" set "WRAPPER_APK=%~dp0base\AndroidWrapper2024.1400.4.968_VM_debug_gamepad_hotplug.apk"
set "APK_ALIGNMENT=16384"

REM Make sure that we actually have game files first
if not exist "%UFO50_SOURCE%data.win" (
	echo Place your UFO 50 game files in "%UFO50_SOURCE%" first, pass the path as the first argument, or set UFO50_SOURCE.
	pause
	exit /b 1
)

if not exist "%UFO50_SOURCE%options.ini" (
	echo ERROR: Missing "%UFO50_SOURCE%options.ini"
	pause
	exit /b 1
)

if not exist "%WRAPPER_APK%" (
	echo ERROR: Missing wrapper APK: "%WRAPPER_APK%"
	pause
	exit /b 1
)

: PREP
REM Clean up from any previous runs
@del UFO50Wrapper.apk 2>nul
@del com.unofficial.ufo50.zip 2>nul
@rmdir /s /q assets 2>nul
@mkdir assets

REM Copy required assets. Keep this discovery-based so new UFO 50 releases work when
REM texture groups, audio groups, fonts, or localization files are added/removed.
echo Preparing assets from "%UFO50_SOURCE%"...
if exist "%UFO50_SOURCE%ext\" robocopy /e /nfl "%UFO50_SOURCE%ext" ".\assets\ext"
if exist "%UFO50_SOURCE%Textures\" robocopy /e /nfl "%UFO50_SOURCE%Textures" ".\assets\Textures"
if exist "%UFO50_SOURCE%fonts\" robocopy /e /nfl "%UFO50_SOURCE%fonts" ".\assets\fonts"
copy "%UFO50_SOURCE%*.dat" ".\assets\"
copy "%UFO50_SOURCE%options.ini" ".\assets\"
copy "%UFO50_SOURCE%data.win" ".\assets\game.droid"
copy "%WRAPPER_APK%" UFO50Wrapper.apk

REM Normalize staged assets to lowercase paths because Android APK assets are case-sensitive
REM and the GameMaker runtime lowercases datafile paths.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$root=(Resolve-Path '.\assets').Path; $tmp=(Resolve-Path '.').Path+'\assets.lowercase'; if(Test-Path $tmp){Remove-Item -Recurse -Force $tmp}; New-Item -ItemType Directory -Path $tmp | Out-Null; Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object { $rel=$_.FullName.Substring($root.Length+1).ToLowerInvariant(); $dest=Join-Path $tmp $rel; New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null; Copy-Item -LiteralPath $_.FullName -Destination $dest }; Remove-Item -Recurse -Force $root; Rename-Item -LiteralPath $tmp -NewName 'assets'"
if errorlevel 1 exit /b !errorlevel!

REM Some current PC builds have trailing bytes after the GameMaker FORM chunk.
REM The Android runner rejects those with "unexpected size", so trim game.droid
REM to the FORM header size when needed.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='.\assets\game.droid'; $fs=[System.IO.File]::Open($p,[System.IO.FileMode]::Open,[System.IO.FileAccess]::ReadWrite); try { $b=New-Object byte[] 8; [void]$fs.Read($b,0,8); if ($b[0] -ne 70 -or $b[1] -ne 79 -or $b[2] -ne 82 -or $b[3] -ne 77) { throw 'assets/game.droid is not a GameMaker FORM file' }; $expected=[BitConverter]::ToUInt32($b,4)+8; $actual=$fs.Length; if ($actual -gt $expected) { Write-Host "Trimming game.droid from $actual to FORM size $expected bytes"; $fs.SetLength($expected) } elseif ($actual -lt $expected) { throw "game.droid is smaller than FORM header size ($actual < $expected)" } } finally { $fs.Close() }"
if errorlevel 1 exit /b !errorlevel!

REM Patch Steamworks extension metadata so calls route to com.unofficial.ufo50.Steamworks.
set "UTMT_CLI=%UTMT_CLI%"
if "%UTMT_CLI%"=="" set "UTMT_CLI=%CD%\bin\utmt\UndertaleModCli.exe"
if not exist "%UTMT_CLI%" (
  echo Downloading UndertaleModCli...
  if exist ".\bin\utmt\" rmdir /s /q ".\bin\utmt"
  mkdir ".\bin\utmt"
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/UnderminersTeam/UndertaleModTool/releases/download/0.9.1.0/UTMT_CLI_v0.9.1.0-Windows.zip' -OutFile '.\utmt.zip'; Expand-Archive '.\utmt.zip' -DestinationPath '.\bin\utmt'"
  if errorlevel 1 exit /b !errorlevel!
  del ".\utmt.zip"
)
echo Patching Steamworks extension metadata for Android...
"%UTMT_CLI%" load .\assets\game.droid -s .\scripts\patch_ufo50_android.csx -o .\assets\game.droid.patched
if errorlevel 1 exit /b !errorlevel!
move /y .\assets\game.droid.patched .\assets\game.droid

REM Clean wrapper apk
REM The base wrapper contains placeholder game.droid/options.ini; replace them.
echo Preparing wrapper...
.\bin\aapt.exe remove -f -v UFO50Wrapper.apk assets/options.ini
.\bin\aapt.exe remove -f -v UFO50Wrapper.apk assets/game.droid

: JAVA
REM Download Java, if needed
if exist ".\bin\java\bin\java.exe" (
  goto PACK
)

REM Clean up whatever currently exists for Java
if exist ".\bin\java\" (
  @rmdir /S /Q ".\bin\java"
)

echo Downloading java...
powershell -Command "$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri 'https://corretto.aws/downloads/resources/21.0.2.13.1/amazon-corretto-21.0.2.13.1-windows-x64-jdk.zip' -OutFile '.\jdk.zip'"

echo Extracting java...
powershell Expand-Archive ".\jdk.zip" -DestinationPath "."

echo Cleaning up...
move ".\jdk21.0.2_13" ".\bin\java"
del ".\jdk.zip"

: PACK
REM Add game assets to base wrapper APK
echo Building wrapper...
for /r assets %%F in (*) do (
	set "asset=%%F"
	set "asset=!asset:%CD%\=!"
	set "asset=!asset:\=/!"
	.\bin\aapt.exe add -f -v UFO50Wrapper.apk "!asset!"
	if errorlevel 1 exit /b !errorlevel!
)

REM Store externally loaded localization/font files without compression.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; $apk='UFO50Wrapper.apk'; $tmp='UFO50Wrapper.apk.tmp'; if(Test-Path $tmp){Remove-Item $tmp}; $zin=[IO.Compression.ZipFile]::OpenRead($apk); $zout=[IO.Compression.ZipFile]::Open($tmp,[IO.Compression.ZipArchiveMode]::Create); try { foreach($entry in $zin.Entries){ $method=[IO.Compression.CompressionLevel]::Optimal; if($entry.FullName.StartsWith('assets/ext/') -or $entry.FullName.StartsWith('assets/fonts/')){ $method=[IO.Compression.CompressionLevel]::NoCompression }; $new=$zout.CreateEntry($entry.FullName,$method); $src=$entry.Open(); $dst=$new.Open(); try { $src.CopyTo($dst) } finally { $dst.Dispose(); $src.Dispose() } } } finally { $zout.Dispose(); $zin.Dispose() }; Move-Item -Force $tmp $apk"
if errorlevel 1 exit /b !errorlevel!

: BUILD
REM Zipalign and sign APK. Use 16 KiB alignment so uncompressed native
REM libraries install on Android devices built with 16 KiB page sizes.
echo Building APK...
.\bin\zipalign.exe -f -v %APK_ALIGNMENT% UFO50Wrapper.apk com.unofficial.ufo50.zipalign.apk
.\bin\java\bin\java.exe -jar .\bin\apksigner.jar sign --key .\base\testkey.pk8 --cert .\base\testkey.x509.pem --out com.unofficial.ufo50.apk com.unofficial.ufo50.zipalign.apk

: CLEAN
REM Clean up
echo Cleaning up...
del com.unofficial.ufo50.zipalign.apk
del com.unofficial.ufo50.apk.idsig 2>nul
del UFO50Wrapper.apk
rmdir /s /q assets

echo Done! Built com.unofficial.ufo50.apk. Have fun.
pause
