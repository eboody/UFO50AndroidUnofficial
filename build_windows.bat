@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "BUILD_EXIT=1"
set "PAUSE_ON_EXIT=0"
if "%~1"=="" set "PAUSE_ON_EXIT=1"

REM Resolve caller-relative inputs before switching to the repository directory.
if not "%~1"=="" (
  set "UFO50_SOURCE=%~f1"
) else if defined UFO50_SOURCE (
  for %%I in ("%UFO50_SOURCE%") do set "UFO50_SOURCE=%%~fI"
) else (
  set "UFO50_SOURCE=%~dp0ufo50"
)

set "ORIENTATION=%~2"
if "%ORIENTATION%"=="" set "ORIENTATION=%UFO50_ORIENTATION%"
if "%ORIENTATION%"=="" set "ORIENTATION=landscape"
if /I "%ORIENTATION%"=="portrait" (
  set "DEFAULT_WRAPPER=%~dp0base\AndroidWrapper2024.1400.4.968_VM_debug_gamepad_hotplug_portrait.apk"
  set "OUTPUT_APK=com.unofficial.ufo50.portrait.apk"
) else if /I "%ORIENTATION%"=="landscape" (
  set "DEFAULT_WRAPPER=%~dp0base\AndroidWrapper2024.1400.4.968_VM_debug_gamepad_hotplug.apk"
  set "OUTPUT_APK=com.unofficial.ufo50.apk"
) else (
  echo ERROR: Orientation must be "landscape" or "portrait", not "%ORIENTATION%".
  exit /b 1
)
set "OUTPUT_PENDING=%OUTPUT_APK%.pending"

if defined UFO50_WRAPPER_APK (
  for %%I in ("%UFO50_WRAPPER_APK%") do set "WRAPPER_APK=%%~fI"
) else (
  set "WRAPPER_APK=%DEFAULT_WRAPPER%"
)

pushd "%~dp0" || (
  echo ERROR: Could not open the build directory: "%~dp0"
  exit /b 1
)

set "APK_ALIGNMENT=4"
set "JAVA=.\bin\java\bin\java.exe"
set "JDK_SHA256=d67abba221a54dbc29df3c0383bfaf0b8fc7128bf4f0e9898d42fc79610a098d"
set "UTMT_SHA256=6dcb937d96f3ee90d2f9add333278b7041ea7980507a8a63f7aa4ca6c77a9c82"
set "UTMT_CLI=%UTMT_CLI%"
if "%UTMT_CLI%"=="" set "UTMT_CLI=%CD%\bin\utmt\UndertaleModCli.exe"

REM Never leave an older or partially signed APK looking like this run's output.
attrib -R ".\%OUTPUT_APK%" 2>nul
attrib -R ".\%OUTPUT_PENDING%" 2>nul
del /f /q ".\%OUTPUT_APK%" 2>nul
del /f /q ".\%OUTPUT_PENDING%" 2>nul
del /f /q ".\%OUTPUT_APK%.idsig" 2>nul
del /f /q ".\%OUTPUT_PENDING%.idsig" 2>nul
if exist ".\%OUTPUT_APK%" (
  echo ERROR: Could not remove the previous output APK.
  goto FAIL
)

if not exist "%UFO50_SOURCE%\data.win" (
  echo ERROR: Missing "%UFO50_SOURCE%\data.win"
  echo Pass the UFO 50 install directory as the first argument, set UFO50_SOURCE,
  echo or copy the complete game installation into "%CD%\ufo50".
  goto FAIL
)

if not exist "%UFO50_SOURCE%\options.ini" (
  echo ERROR: Missing "%UFO50_SOURCE%\options.ini"
  goto FAIL
)

if not exist "%WRAPPER_APK%" (
  echo ERROR: Missing wrapper APK: "%WRAPPER_APK%"
  goto FAIL
)

REM Java powers the portable asset preparation helper and APK signer. Use curl
REM and tar included with supported Windows 10/11 releases so execution-policy
REM restrictions cannot block the build or its large HTTPS downloads.
if not exist "%JAVA%" (
  where curl.exe >nul 2>nul || (
    echo ERROR: curl.exe is required. Install current Windows updates and try again.
    goto FAIL
  )
  where tar.exe >nul 2>nul || (
    echo ERROR: tar.exe is required. Install current Windows updates and try again.
    goto FAIL
  )

  echo Downloading Java...
  if exist ".\bin\java\" rmdir /s /q ".\bin\java"
  del ".\jdk.zip" 2>nul
  curl.exe -fL --retry 3 --retry-delay 2 -o ".\jdk.zip" "https://corretto.aws/downloads/resources/21.0.6.7.1/amazon-corretto-21.0.6.7.1-windows-x64-jdk.zip"
  if errorlevel 1 goto FAIL
  certutil -hashfile ".\jdk.zip" SHA256 | findstr /i /c:"%JDK_SHA256%" >nul
  if errorlevel 1 (
    echo ERROR: The downloaded Java archive failed SHA-256 verification.
    goto FAIL
  )

  echo Extracting Java...
  rmdir /s /q ".\jdk.extract" 2>nul
  mkdir ".\jdk.extract"
  if errorlevel 1 goto FAIL
  tar.exe -xf ".\jdk.zip" -C ".\jdk.extract"
  if errorlevel 1 goto FAIL
  if not exist ".\jdk.extract\jdk21.0.6_7\bin\java.exe" goto FAIL
  move ".\jdk.extract\jdk21.0.6_7" ".\bin\java" >nul
  if errorlevel 1 goto FAIL
  rmdir /s /q ".\jdk.extract"
  del ".\jdk.zip"
)

if not exist "%JAVA%" (
  echo ERROR: Java was not installed at "%JAVA%"
  goto FAIL
)

REM Download UndertaleModCli only when it is not already cached or overridden.
if not exist "%UTMT_CLI%" (
  where curl.exe >nul 2>nul || (
    echo ERROR: curl.exe is required. Install current Windows updates and try again.
    goto FAIL
  )
  where tar.exe >nul 2>nul || (
    echo ERROR: tar.exe is required. Install current Windows updates and try again.
    goto FAIL
  )

  echo Downloading UndertaleModCli...
  del ".\utmt.zip" 2>nul
  curl.exe -fL --retry 3 --retry-delay 2 -o ".\utmt.zip" "https://github.com/UnderminersTeam/UndertaleModTool/releases/download/0.9.1.0/UTMT_CLI_v0.9.1.0-Windows.zip"
  if errorlevel 1 goto FAIL
  certutil -hashfile ".\utmt.zip" SHA256 | findstr /i /c:"%UTMT_SHA256%" >nul
  if errorlevel 1 (
    echo ERROR: The downloaded UndertaleModCli archive failed SHA-256 verification.
    goto FAIL
  )
  rmdir /s /q ".\bin\utmt.extract" 2>nul
  mkdir ".\bin\utmt.extract"
  if errorlevel 1 goto FAIL
  tar.exe -xf ".\utmt.zip" -C ".\bin\utmt.extract"
  if errorlevel 1 goto FAIL
  if not exist ".\bin\utmt.extract\UndertaleModCli.exe" goto FAIL
  if exist ".\bin\utmt\" rmdir /s /q ".\bin\utmt"
  move ".\bin\utmt.extract" ".\bin\utmt" >nul
  if errorlevel 1 goto FAIL
  del ".\utmt.zip"
)

if not exist "%UTMT_CLI%" (
  echo ERROR: UndertaleModCli was not installed at "%UTMT_CLI%"
  goto FAIL
)

REM Clean up from previous successful or interrupted runs.
del ".\UFO50Wrapper.apk" 2>nul
del ".\com.unofficial.ufo50.zipalign.apk" 2>nul
rmdir /s /q ".\assets" 2>nul
rmdir /s /q ".\assets.lowercase" 2>nul
rmdir /s /q ".\assets.backup" 2>nul

echo Preparing assets from "%UFO50_SOURCE%"...
"%JAVA%" ".\scripts\WindowsBuildTools.java" stage "%UFO50_SOURCE%" ".\assets"
if errorlevel 1 goto FAIL

REM Android APK assets are case-sensitive while the GameMaker runtime lowercases
REM datafile paths. The helper also trims bytes after the GameMaker FORM chunk.
"%JAVA%" ".\scripts\WindowsBuildTools.java" prepare ".\assets"
if errorlevel 1 goto FAIL

echo Patching Steamworks extension metadata for Android...
"%UTMT_CLI%" load ".\assets\game.droid" -s ".\scripts\patch_ufo50_android.csx" -o ".\assets\game.droid.patched"
if errorlevel 1 goto FAIL
move /y ".\assets\game.droid.patched" ".\assets\game.droid" >nul
if errorlevel 1 goto FAIL

copy "%WRAPPER_APK%" ".\UFO50Wrapper.apk" >nul
if errorlevel 1 goto FAIL

echo Preparing wrapper...
.\bin\aapt.exe remove -f -v ".\UFO50Wrapper.apk" assets/options.ini
if errorlevel 1 goto FAIL
.\bin\aapt.exe remove -f -v ".\UFO50Wrapper.apk" assets/game.droid
if errorlevel 1 goto FAIL

echo Building wrapper...
"%JAVA%" ".\scripts\WindowsBuildTools.java" add-assets ".\bin\aapt.exe" ".\UFO50Wrapper.apk" ".\assets"
if errorlevel 1 goto FAIL

REM GameMaker opens localization and font assets through file descriptors, so
REM these entries must be stored without compression.
"%JAVA%" ".\scripts\WindowsBuildTools.java" store-apk ".\UFO50Wrapper.apk"
if errorlevel 1 goto FAIL

REM Page-align uncompressed native libraries and 4-byte-align all other stored
REM entries. The wrapper extracts native libraries for 16 KiB-page devices.
REM Validate the exact signed APK before reporting success.
echo Building APK...
.\bin\zipalign.exe -p -f -v %APK_ALIGNMENT% ".\UFO50Wrapper.apk" ".\com.unofficial.ufo50.zipalign.apk"
if errorlevel 1 goto FAIL
"%JAVA%" -jar ".\bin\apksigner.jar" sign --key ".\base\testkey.pk8" --cert ".\base\testkey.x509.pem" --out ".\%OUTPUT_PENDING%" ".\com.unofficial.ufo50.zipalign.apk"
if errorlevel 1 goto FAIL
"%JAVA%" -jar ".\bin\apksigner.jar" verify --verbose ".\%OUTPUT_PENDING%"
if errorlevel 1 goto FAIL
.\bin\zipalign.exe -c -p -v %APK_ALIGNMENT% ".\%OUTPUT_PENDING%"
if errorlevel 1 goto FAIL
move /y ".\%OUTPUT_PENDING%" ".\%OUTPUT_APK%" >nul
if errorlevel 1 goto FAIL

echo Cleaning up...
del ".\com.unofficial.ufo50.zipalign.apk"
del ".\%OUTPUT_APK%.idsig" 2>nul
del ".\%OUTPUT_PENDING%.idsig" 2>nul
del ".\UFO50Wrapper.apk"
rmdir /s /q ".\assets"
set "BUILD_EXIT=0"
echo Done! Built "%CD%\%OUTPUT_APK%". Have fun.
goto END

:FAIL
if not "%ERRORLEVEL%"=="0" set "BUILD_EXIT=%ERRORLEVEL%"
attrib -R ".\%OUTPUT_APK%" 2>nul
attrib -R ".\%OUTPUT_PENDING%" 2>nul
del /f /q ".\%OUTPUT_APK%" 2>nul
del /f /q ".\%OUTPUT_PENDING%" 2>nul
del /f /q ".\%OUTPUT_PENDING%.idsig" 2>nul
echo.
echo ERROR: Build failed. Temporary files were kept for troubleshooting.

:END
popd
if "%PAUSE_ON_EXIT%"=="1" pause
exit /b %BUILD_EXIT%