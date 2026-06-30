# UFO50AndroidUnofficial
A tool to build your own Android version of UFO 50

Love UFO 50? Own an Android device and a controller? Then you can enjoy UFO 50 on the go!
It's an extremely simple process to build your own copy and get it running.
Please do not share your APK with others. Mossmouth created an incredible game and
pirating it would be a serious dick move. Don't screw over indie developers.

Current UFO 50 releases are supported by dynamically packaging the game data files that ship with your local copy.
The default Android wrapper uses GameMaker runtime 2024.1400.4.968 for compatibility with the current Steam build, includes a controller hotplug patch so Bluetooth controllers can be detected after the app is already open, and targets Android 9/API 28 while supporting Android 5.0+ devices.

## Building
0. Purchase and install UFO 50. The devs deserve the money.
1. Download or clone this repo.
2. Find your UFO 50 install folder. It must contain `data.win` and `options.ini`.
3. Run the build script for your computer:

### Windows
Double-click `build_windows.bat`, or open Command Prompt in this repo and run:

```bat
build_windows.bat "C:\Program Files (x86)\Steam\steamapps\common\UFO 50"
```

If you omit the path, copy/merge your UFO 50 files into this repo's `ufo50` folder first, then run `build_windows.bat`.

### Linux
Open a terminal in this repo and run:

```sh
chmod +x build_linux
./build_linux "$HOME/.steam/steam/steamapps/common/UFO 50"
```

If your Steam library is somewhere else, replace the path with your UFO 50 install folder. The Linux script requires `wget`, `unzip`, and `python3`; install them with your distro's package manager if the script reports they are missing.

### macOS
Open Terminal in this repo and run:

```sh
chmod +x build_macos.sh
./build_macos.sh "$HOME/Library/Application Support/Steam/steamapps/common/UFO 50"
```

If your Steam library is somewhere else, replace the path with your UFO 50 install folder. The macOS script requires `wget`, `unzip`, and `python3`; if `wget` is missing, install it with Homebrew: `brew install wget`.

After the script finishes:
1. Copy `com.unofficial.ufo50.apk` to your Android device.
2. Enable installing from unofficial sources on your device, if needed. This varies from device to device.
3. Install `com.unofficial.ufo50.apk` with your file manager of choice. You can delete the APK file after it's installed.
4. Play! You can press Start, go to Settings > Video Settings, and set SCALE to FILL to fill the entire screen.

If you copy files manually, merge/replace the whole UFO 50 install into `ufo50/` instead of skipping duplicates. The build needs the current `data.win`, `options.ini`, `*.dat`, `Textures/`, `ext/`, and `fonts/` files from your installed game.

## Troubleshooting
- **Crash immediately after the cover art/splash screen:** rebuild from a fresh checkout or pull the latest version of this repo. Older builds targeted a newer Android SDK and could crash on handhelds such as MagicX Mini Zero 28/Android 10 or MagicX One35/Android 12.
- **"Error parsing the package":** delete the old APK from the device, rebuild, copy the new `com.unofficial.ufo50.apk`, and install that file again. If Android still rejects it, confirm the downloaded/copied APK size matches the one on your computer and that the device is running Android 5.0 or newer.
- **Missing text/audio/textures or startup crashes after replacing files:** make sure you did not skip duplicate files when copying the game directory. Re-copy the game files and choose replace/merge, or pass the game install path directly to the build script.

## Save Management
Before you can manage save files, make sure you have enabled Developer Options on your device and allowed USB or Wi-Fi debugging. Make sure you have run UFO 50 at least once before you attempt to upload your saves.
To backup your save, run `backup_saves_windows.bat` on Windows, `backup_saves_linux` on Linux, or `backup_saves_macos.sh` on macOS.
This will copy your save files from your device and put them in the save folder.
To upload/restore your save, place your save files into the save folder and run `upload_saves_windows.bat` on Windows, `upload_saves_linux` on Linux, or `upload_saves_macos.sh` on macOS.

## Notes
If you have UFO 50 working on PortMaster, open ufo50.port in an archive manager like 7-zip and use the game.droid and options.ini files in that directory.
If you don't have any idea what the above means, don't worry about it. It's entirely optional.

## To-Do
- Integrate PortMaster's changes into build script as an optional selection
- Implement touch controls (may never happen, need to research injecting objects using UndertaleModTool