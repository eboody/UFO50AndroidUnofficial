import json
import os
import shutil
import struct
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "scripts" / "WindowsBuildTools.java"


def insert_stale_central_directory(apk: Path) -> None:
    with zipfile.ZipFile(apk) as archive:
        insertion_offset = archive.getinfo("assets/ext/english/0_text.json").header_offset

    with tempfile.TemporaryDirectory() as temp_dir:
        stale_zip = Path(temp_dir) / "stale.zip"
        with zipfile.ZipFile(stale_zip, "w") as archive:
            archive.writestr("base/runner.bin", b"runner")
        stale_data = stale_zip.read_bytes()
        stale_eocd = stale_data.rfind(b"PK\x05\x06")
        stale_central_offset = struct.unpack_from("<I", stale_data, stale_eocd + 16)[0]
        stale_directory = stale_data[stale_central_offset:]

    data = bytearray(apk.read_bytes())
    original_eocd = data.rfind(b"PK\x05\x06")
    original_central_offset = struct.unpack_from("<I", data, original_eocd + 16)[0]
    entry_count = struct.unpack_from("<H", data, original_eocd + 10)[0]
    data[insertion_offset:insertion_offset] = stale_directory

    shift = len(stale_directory)
    final_eocd = original_eocd + shift
    final_central_offset = original_central_offset + shift
    struct.pack_into("<I", data, final_eocd + 16, final_central_offset)
    central_entry = final_central_offset
    for _ in range(entry_count):
        relative_offset = struct.unpack_from("<I", data, central_entry + 42)[0]
        if relative_offset >= insertion_offset:
            struct.pack_into("<I", data, central_entry + 42, relative_offset + shift)
        name_length, extra_length, comment_length = struct.unpack_from(
            "<HHH", data, central_entry + 28
        )
        central_entry += 46 + name_length + extra_length + comment_length
    apk.write_bytes(data)


class WindowsBuildToolsTest(unittest.TestCase):
    def run_tool(self, *args: object) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["java", str(TOOL), *(str(arg) for arg in args)],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )

    def test_stage_copies_current_game_layout_without_fixed_asset_names(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "UFO 50 source"
            assets = Path(temp_dir) / "staged assets"
            (source / "Textures").mkdir(parents=True)
            (source / "Textures" / "new_texture.yytex").write_bytes(b"texture")
            (source / "ext").mkdir()
            (source / "ext" / "language.json").write_text("{}")
            (source / "fonts").mkdir()
            (source / "fonts" / "font.bin").write_bytes(b"font")
            (source / "audiogroup_new.dat").write_bytes(b"audio")
            (source / "options.ini").write_text("[options]")
            (source / "data.win").write_bytes(b"game")
            (source / "unrelated.exe").write_bytes(b"skip")

            result = self.run_tool("stage", source, assets)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((assets / "Textures" / "new_texture.yytex").read_bytes(), b"texture")
            self.assertEqual((assets / "ext" / "language.json").read_text(), "{}")
            self.assertEqual((assets / "fonts" / "font.bin").read_bytes(), b"font")
            self.assertEqual((assets / "audiogroup_new.dat").read_bytes(), b"audio")
            self.assertEqual((assets / "options.ini").read_text(), "[options]")
            self.assertEqual((assets / "game.droid").read_bytes(), b"game")
            self.assertFalse((assets / "unrelated.exe").exists())

    def test_stage_rejects_source_destination_overlap_without_deleting_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            source = Path(temp_dir) / "assets"
            source.mkdir()
            (source / "data.win").write_bytes(b"game")
            (source / "options.ini").write_text("[options]")

            result = self.run_tool("stage", source, source)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("overlap", result.stderr.lower())
            self.assertEqual((source / "data.win").read_bytes(), b"game")
            self.assertEqual((source / "options.ini").read_text(), "[options]")

    @unittest.skipIf(os.name == "nt", "requires POSIX symlink creation")
    def test_stage_rejects_symlink_alias_overlap_without_deleting_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            assets = Path(temp_dir) / "assets"
            assets.mkdir()
            (assets / "data.win").write_bytes(b"game")
            (assets / "options.ini").write_text("[options]")
            source_alias = Path(temp_dir) / "source-alias"
            source_alias.symlink_to(assets, target_is_directory=True)

            result = self.run_tool("stage", source_alias, assets)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("overlap", result.stderr.lower())
            self.assertEqual((assets / "data.win").read_bytes(), b"game")
            self.assertEqual((assets / "options.ini").read_text(), "[options]")

    @unittest.skipIf(os.name == "nt", "uses a POSIX fake executable")
    def test_add_assets_passes_literal_special_character_paths_to_aapt(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            assets = root / "assets"
            assets.mkdir()
            names = ["space name.dat", "bang!file.dat", "pct%PATH%file.dat", "amp&file.dat", "paren(file).dat"]
            for name in names:
                (assets / name).write_bytes(b"asset")
            log = root / "arguments.jsonl"
            fake_aapt = root / "fake-aapt"
            fake_aapt.write_text(
                "#!/usr/bin/env python3\n"
                "import json, sys\n"
                f"with open({str(log)!r}, 'a') as output:\n"
                "    output.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            )
            fake_aapt.chmod(0o755)

            result = self.run_tool("add-assets", fake_aapt, root / "wrapper.apk", assets)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            invocations = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual({args[-1] for args in invocations}, {f"assets/{name}" for name in names})
            self.assertTrue(all(args[:3] == ["add", "-f", "-v"] for args in invocations))

    def test_prepare_normalizes_paths_and_trims_form_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            assets = Path(temp_dir) / "Assets"
            (assets / "Textures" / "Nested").mkdir(parents=True)
            (assets / "Textures" / "Nested" / "Image.YYTEX").write_bytes(b"texture")
            (assets / "EXT" / "ENGLISH").mkdir(parents=True)
            (assets / "EXT" / "ENGLISH" / "0_Text.JSON").write_text("{}")
            form_payload = b"payload"
            (assets / "game.droid").write_bytes(
                b"FORM" + struct.pack("<I", len(form_payload)) + form_payload + b"trailing"
            )

            result = self.run_tool("prepare", assets)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((assets / "textures" / "nested" / "image.yytex").is_file())
            self.assertTrue((assets / "ext" / "english" / "0_text.json").is_file())
            self.assertFalse((assets / "Textures").exists())
            self.assertEqual(
                (assets / "game.droid").read_bytes(),
                b"FORM" + struct.pack("<I", len(form_payload)) + form_payload,
            )

    def test_prepare_rejects_case_collisions_without_replacing_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            assets = Path(temp_dir) / "assets"
            assets.mkdir()
            (assets / "A.dat").write_bytes(b"upper")
            (assets / "a.dat").write_bytes(b"lower")
            (assets / "game.droid").write_bytes(b"FORM" + struct.pack("<I", 0))

            result = self.run_tool("prepare", assets)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("lowercase path collision", result.stderr.lower())
            self.assertEqual((assets / "A.dat").read_bytes(), b"upper")
            self.assertEqual((assets / "a.dat").read_bytes(), b"lower")

    def test_store_apk_leaves_external_assets_uncompressed(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            apk = Path(temp_dir) / "wrapper.apk"
            with zipfile.ZipFile(apk, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("base/runner.bin", b"runner")
            # aapt adds assets after the original ZIP's central directory.
            # Sequential ZIP readers stop at that old directory and silently omit them.
            with zipfile.ZipFile(apk, "a", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("empty/", b"")
                archive.writestr("assets/ext/english/0_text.json", "{}")
                archive.writestr("assets/fonts/font.bin", b"font")
                archive.writestr("assets/game.droid", b"game")
            insert_stale_central_directory(apk)

            with zipfile.ZipFile(apk) as archive:
                expected_contents = {
                    info.filename: archive.read(info.filename)
                    for info in archive.infolist()
                    if not info.is_dir()
                }
                expected_names = {info.filename for info in archive.infolist()}

            result = self.run_tool("store-apk", apk)

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            with zipfile.ZipFile(apk) as archive:
                self.assertEqual({info.filename for info in archive.infolist()}, expected_names)
                self.assertEqual(
                    {
                        info.filename: archive.read(info.filename)
                        for info in archive.infolist()
                        if not info.is_dir()
                    },
                    expected_contents,
                )
                self.assertEqual(
                    archive.getinfo("assets/ext/english/0_text.json").compress_type,
                    zipfile.ZIP_STORED,
                )
                self.assertEqual(
                    archive.getinfo("assets/fonts/font.bin").compress_type,
                    zipfile.ZIP_STORED,
                )
                self.assertEqual(
                    archive.getinfo("assets/game.droid").compress_type,
                    zipfile.ZIP_DEFLATED,
                )
                self.assertEqual(archive.read("base/runner.bin"), b"runner")
                self.assertEqual(archive.read("assets/ext/english/0_text.json"), b"{}")

    def test_windows_build_has_no_powershell_dependency_and_checks_output(self) -> None:
        script = (ROOT / "build_windows.bat").read_text()

        self.assertNotIn("powershell", script.lower())
        self.assertIn('pushd "%~dp0"', script.lower())
        self.assertNotIn("call :add_asset", script.lower())
        self.assertIn("windowsbuildtools.java\" add-assets", script.lower())
        self.assertIn("d67abba221a54dbc29df3c0383bfaf0b8fc7128bf4f0e9898d42fc79610a098d", script.lower())
        self.assertIn("6dcb937d96f3ee90d2f9add333278b7041ea7980507a8a63f7aa4ca6c77a9c82", script.lower())
        self.assertIn("com.unofficial.ufo50.apk.pending", script.lower())
        self.assertRegex(script.lower(), r'apksigner\.jar"?\s+verify')
        self.assertIn('set "apk_alignment=4"', script.lower())
        self.assertIn("zipalign.exe -p -f -v %apk_alignment%", script.lower())
        self.assertIn("zipalign.exe -c -p -v %apk_alignment%", script.lower())

        lowered = script.lower()
        self.assertLess(lowered.index("curl.exe", lowered.index("downloading java")), lowered.index("jdk_sha256", lowered.index("downloading java")))
        self.assertLess(lowered.index("jdk_sha256", lowered.index("downloading java")), lowered.index("tar.exe -xf", lowered.index("downloading java")))

    @unittest.skipUnless(shutil.which("wine"), "Wine is required for cmd.exe behavior")
    def test_windows_build_removes_read_only_stale_output_before_failure(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            shutil.copy2(ROOT / "build_windows.bat", root / "build_windows.bat")
            stale = root / "com.unofficial.ufo50.apk"
            stale.write_bytes(b"stale")
            stale.chmod(0o444)
            batch = subprocess.run(
                ["winepath", "-w", str(root / "build_windows.bat")],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            result = subprocess.run(
                ["wine", "cmd", "/d", "/c", batch, "Z:\\definitely-missing-ufo50"],
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(stale.exists(), result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
