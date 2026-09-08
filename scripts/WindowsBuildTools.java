import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.channels.FileChannel;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.nio.file.attribute.FileTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;

public final class WindowsBuildTools {
    private static final int BUFFER_SIZE = 1024 * 1024;

    private WindowsBuildTools() {}

    public static void main(String[] args) {
        try {
            run(args);
        } catch (Exception error) {
            System.err.println("ERROR: " + error.getMessage());
            System.exit(1);
        }
    }

    private static void run(String[] args) throws IOException {
        if (args.length == 3 && args[0].equals("stage")) {
            stageAssets(Path.of(args[1]), Path.of(args[2]));
            return;
        }
        if (args.length == 4 && args[0].equals("add-assets")) {
            addAssets(Path.of(args[1]), Path.of(args[2]), Path.of(args[3]));
            return;
        }
        if (args.length == 2 && args[0].equals("prepare")) {
            normalizeAndTrim(Path.of(args[1]));
            return;
        }
        if (args.length == 2 && args[0].equals("store-apk")) {
            storeExternalAssets(Path.of(args[1]));
            return;
        }
        throw new IllegalArgumentException(
            "usage: WindowsBuildTools.java stage SOURCE ASSETS | add-assets AAPT APK ASSETS | "
                + "prepare ASSETS | store-apk APK"
        );
    }

    private static void stageAssets(Path source, Path assets) throws IOException {
        source = source.toRealPath();
        assets = assets.toAbsolutePath().normalize();
        requireFile(source.resolve("data.win"));
        requireFile(source.resolve("options.ini"));
        Path comparableAssets = Files.exists(assets)
            ? assets.toRealPath()
            : assets.getParent().toRealPath().resolve(assets.getFileName()).normalize();
        if (source.startsWith(comparableAssets) || comparableAssets.startsWith(source)) {
            throw new IOException("source and destination overlap: " + source + " and " + assets);
        }

        deleteTree(assets);
        Files.createDirectories(assets);
        try {
            copyOptionalTree(source.resolve("ext"), assets.resolve("ext"));
            copyOptionalTree(source.resolve("Textures"), assets.resolve("Textures"));
            copyOptionalTree(source.resolve("fonts"), assets.resolve("fonts"));
            try (var children = Files.list(source)) {
                for (Path child : (Iterable<Path>) children::iterator) {
                    String name = child.getFileName().toString();
                    if (Files.isRegularFile(child) && name.toLowerCase(Locale.ROOT).endsWith(".dat")) {
                        Files.copy(child, assets.resolve(name), StandardCopyOption.REPLACE_EXISTING);
                    }
                }
            }
            Files.copy(source.resolve("options.ini"), assets.resolve("options.ini"));
            Files.copy(source.resolve("data.win"), assets.resolve("game.droid"));
        } catch (Exception error) {
            deleteTree(assets);
            throw error;
        }
    }

    private static void addAssets(Path aapt, Path apk, Path assets) throws IOException {
        aapt = aapt.toAbsolutePath().normalize();
        apk = apk.toAbsolutePath().normalize();
        assets = assets.toAbsolutePath().normalize();
        requireFile(aapt);
        if (!Files.isDirectory(assets)) {
            throw new IOException("assets directory not found: " + assets);
        }

        Path workingDirectory = assets.getParent();
        List<Path> files = new ArrayList<>();
        try (var paths = Files.walk(assets)) {
            for (Path path : (Iterable<Path>) paths::iterator) {
                if (Files.isRegularFile(path)) {
                    files.add(path);
                }
            }
        }
        files.sort(Comparator.comparing(path -> path.toString().toLowerCase(Locale.ROOT)));

        for (Path file : files) {
            String relative = workingDirectory.relativize(file).toString().replace(File.separatorChar, '/');
            Process process = new ProcessBuilder(
                aapt.toString(), "add", "-f", "-v", apk.toString(), relative
            )
                .directory(workingDirectory.toFile())
                .inheritIO()
                .start();
            int exitCode;
            try {
                exitCode = process.waitFor();
            } catch (InterruptedException error) {
                Thread.currentThread().interrupt();
                throw new IOException("interrupted while adding " + relative, error);
            }
            if (exitCode != 0) {
                throw new IOException("aapt failed with exit code " + exitCode + " while adding " + relative);
            }
        }
    }

    private static void copyOptionalTree(Path source, Path destination) throws IOException {
        if (!Files.isDirectory(source)) {
            return;
        }
        try (var paths = Files.walk(source)) {
            for (Path path : (Iterable<Path>) paths::iterator) {
                Path target = destination.resolve(source.relativize(path).toString());
                if (Files.isDirectory(path)) {
                    Files.createDirectories(target);
                } else {
                    Files.createDirectories(target.getParent());
                    Files.copy(path, target, StandardCopyOption.REPLACE_EXISTING);
                }
            }
        }
    }

    private static void normalizeAndTrim(Path assets) throws IOException {
        assets = assets.toAbsolutePath().normalize();
        if (!Files.isDirectory(assets)) {
            throw new IOException("assets directory not found: " + assets);
        }

        Path staged = assets.resolveSibling(assets.getFileName() + ".lowercase");
        Path backup = assets.resolveSibling(assets.getFileName() + ".backup");
        deleteTree(staged);
        deleteTree(backup);

        List<Path> files = new ArrayList<>();
        Map<Path, Path> normalizedOwners = new HashMap<>();
        try (var paths = Files.walk(assets)) {
            for (Path path : (Iterable<Path>) paths::iterator) {
                if (!Files.isRegularFile(path)) {
                    continue;
                }
                Path relative = assets.relativize(path);
                Path normalized = lowercase(relative);
                Path prior = normalizedOwners.putIfAbsent(normalized, relative);
                if (prior != null && !prior.equals(relative)) {
                    throw new IOException(
                        "lowercase path collision: " + prior + " and " + relative + " both become " + normalized
                    );
                }
                files.add(path);
            }
        }

        Files.createDirectories(staged);
        try {
            for (Path source : files) {
                Path destination = staged.resolve(lowercase(assets.relativize(source)));
                Files.createDirectories(destination.getParent());
                Files.copy(source, destination, StandardCopyOption.COPY_ATTRIBUTES);
            }
            trimGameData(staged.resolve("game.droid"));
            Files.move(assets, backup);
            try {
                Files.move(staged, assets);
            } catch (Exception error) {
                Files.move(backup, assets);
                throw error;
            }
            deleteTree(backup);
        } catch (Exception error) {
            deleteTree(staged);
            throw error;
        }
    }

    private static Path lowercase(Path path) {
        Path lowered = Path.of("");
        for (Path part : path) {
            lowered = lowered.resolve(part.toString().toLowerCase(Locale.ROOT));
        }
        return lowered;
    }

    private static void trimGameData(Path gameData) throws IOException {
        requireFile(gameData);
        long actual = Files.size(gameData);
        if (actual < 8) {
            throw new IOException("assets/game.droid is not a GameMaker FORM file");
        }

        ByteBuffer header = ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN);
        try (FileChannel channel = FileChannel.open(gameData, StandardOpenOption.READ, StandardOpenOption.WRITE)) {
            while (header.hasRemaining() && channel.read(header) >= 0) {
                // Continue until the complete header has been read.
            }
            byte[] bytes = header.array();
            if (bytes[0] != 'F' || bytes[1] != 'O' || bytes[2] != 'R' || bytes[3] != 'M') {
                throw new IOException("assets/game.droid is not a GameMaker FORM file");
            }
            long expected = Integer.toUnsignedLong(header.getInt(4)) + 8L;
            if (actual > expected) {
                System.out.println("Trimming game.droid from " + actual + " to FORM size " + expected + " bytes");
                channel.truncate(expected);
            } else if (actual < expected) {
                throw new IOException(
                    "game.droid is smaller than FORM header size (" + actual + " < " + expected + ")"
                );
            }
        }
    }

    private static void storeExternalAssets(Path apk) throws IOException {
        apk = apk.toAbsolutePath().normalize();
        requireFile(apk);
        Path temporary = apk.resolveSibling(apk.getFileName() + ".tmp");
        Files.deleteIfExists(temporary);

        byte[] buffer = new byte[BUFFER_SIZE];
        try (
            ZipFile input = new ZipFile(apk.toFile());
            ZipOutputStream output = new ZipOutputStream(new BufferedOutputStream(Files.newOutputStream(temporary)))
        ) {
            Enumeration<? extends ZipEntry> entries = input.entries();
            while (entries.hasMoreElements()) {
                ZipEntry sourceEntry = entries.nextElement();
                boolean stored = sourceEntry.getMethod() == ZipEntry.STORED
                    || sourceEntry.getName().startsWith("assets/ext/")
                    || sourceEntry.getName().startsWith("assets/fonts/");
                ZipEntry targetEntry = copyMetadata(sourceEntry);
                try (InputStream entryInput = new BufferedInputStream(input.getInputStream(sourceEntry))) {
                    if (stored && !sourceEntry.isDirectory()) {
                        targetEntry.setMethod(ZipEntry.STORED);
                        targetEntry.setSize(sourceEntry.getSize());
                        targetEntry.setCompressedSize(sourceEntry.getSize());
                        targetEntry.setCrc(sourceEntry.getCrc());
                        output.putNextEntry(targetEntry);
                        copy(entryInput, output, buffer);
                    } else {
                        targetEntry.setMethod(ZipEntry.DEFLATED);
                        output.putNextEntry(targetEntry);
                        copy(entryInput, output, buffer);
                    }
                }
                output.closeEntry();
            }
        } catch (Exception error) {
            Files.deleteIfExists(temporary);
            throw error;
        }
        Files.move(temporary, apk, StandardCopyOption.REPLACE_EXISTING);
    }

    private static ZipEntry copyMetadata(ZipEntry source) {
        ZipEntry target = new ZipEntry(source.getName());
        FileTime modified = source.getLastModifiedTime();
        if (modified != null) {
            target.setLastModifiedTime(modified);
        }
        if (source.getComment() != null) {
            target.setComment(source.getComment());
        }
        return target;
    }

    private static void copy(InputStream input, OutputStream output, byte[] buffer) throws IOException {
        int count;
        while ((count = input.read(buffer)) >= 0) {
            if (count > 0) {
                output.write(buffer, 0, count);
            }
        }
    }

    private static void requireFile(Path path) throws IOException {
        if (!Files.isRegularFile(path)) {
            throw new IOException("required file not found: " + path);
        }
    }

    private static void deleteTree(Path root) throws IOException {
        if (!Files.exists(root)) {
            return;
        }
        Files.walkFileTree(root, new SimpleFileVisitor<Path>() {
            @Override
            public FileVisitResult visitFile(Path file, BasicFileAttributes attributes) throws IOException {
                Files.delete(file);
                return FileVisitResult.CONTINUE;
            }

            @Override
            public FileVisitResult postVisitDirectory(Path directory, IOException error) throws IOException {
                if (error != null) {
                    throw error;
                }
                Files.delete(directory);
                return FileVisitResult.CONTINUE;
            }
        });
    }
}
