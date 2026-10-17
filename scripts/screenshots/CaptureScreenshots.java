// SPDX-License-Identifier: GPL-3.0-only
//JAVA 25+
//JAVA_OPTIONS -Djava.awt.headless=true

import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.TreeMap;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import javax.imageio.ImageIO;

public class CaptureScreenshots {
  private static final AtomicReference<Session> SESSION = new AtomicReference<>();
  private static final List<Process> COMMANDS = new ArrayList<>();

  record Session(Process process, Path directory) {}

  public static void main(String... args) throws Exception {
    if (List.of(args).equals(List.of("--self-test"))) {
      selfTest();
      return;
    }
    boolean hardware = List.of(args).equals(List.of("--hardware"));
    if (args.length != 0 && !hardware) {
      throw new IllegalArgumentException("usage: CaptureScreenshots.java [--hardware|--self-test]");
    }
    if (!System.getProperty("os.name").equals("Mac OS X")) {
      throw new IllegalStateException("Screenshots require an interactive macOS desktop.");
    }
    Path root = Path.of("").toAbsolutePath();
    Files.createDirectories(root.resolve(".build"));
    try (var channel = FileChannel.open(root.resolve(".build/screenshots.lock"),
        StandardOpenOption.CREATE, StandardOpenOption.WRITE); var lock = channel.tryLock()) {
      if (lock == null) throw new IOException("Another screenshot run is already active.");
      Thread cleanup = new Thread(CaptureScreenshots::cleanup, "screenshot-cleanup");
      Runtime.getRuntime().addShutdownHook(cleanup);
      Path temporary = Files.createTempDirectory("NotifyPoint-screenshots-");
      boolean succeeded = false;
      try {
        capture(root, temporary, hardware);
        succeeded = true;
      } finally {
        cleanup();
        Runtime.getRuntime().removeShutdownHook(cleanup);
        if (Files.exists(temporary.resolve("backups"))) {
          System.err.println("Asset publication failed; recovery copies retained at " + temporary.resolve("backups"));
        } else if (succeeded) {
          deleteTree(temporary);
        } else {
          System.err.println("Screenshot diagnostics retained at " + temporary);
        }
      }
    }
  }

  private static void capture(Path root, Path temporary, boolean hardware) throws Exception {
    Path bundle = temporary.resolve("NotifyPoint.app");
    command(root, Duration.ofMinutes(5), "make", "build", "APP_BUNDLE=" + bundle,
        "BUILD_INFO_SWIFT=" + temporary.resolve("BuildInfo.generated.swift"));
    if (!confirmCapture(root)) {
      System.out.println("Screenshot capture cancelled. Documentation assets were left unchanged.");
      return;
    }
    var staged = new LinkedHashMap<Path, Path>();
    var metadata = new TreeMap<String, String>();
    Path metadataFile = root.resolve(".github/menu-screenshots.properties");
    if (Files.exists(metadataFile)) {
      Properties previous = readProperties(metadataFile);
      previous.forEach((key, value) -> metadata.put(key.toString(), value.toString()));
    }
    String osVersion = output(root, "sw_vers", "-productVersion").strip();
    String osBuild = output(root, "sw_vers", "-buildVersion").strip();
    for (String scene : List.of("position", "display")) {
      for (String appearance : List.of("light", "dark")) {
        String name = (scene.equals("position") ? "menu-screenshot" : "menu-display-screenshot")
            + (appearance.equals("dark") ? "-dark" : "") + ".png";
        Path directory = Files.createDirectory(temporary.resolve(scene + "-" + appearance));
        String background = appearance.equals("dark") ? "background-dark.png" : "background.png";
        Files.copy(root.resolve("scripts/screenshots/" + background), directory.resolve("background.png"));
        Files.writeString(directory.resolve("settings.json"), """
            {"debugMode":false,"notificationPosition":"deadCenter","notificationDisplayTarget":"%s"}
            """.formatted(scene.equals("display") ? "builtInDisplay" : "mainDisplay"));
        var arguments = new ArrayList<>(List.of(bundle.resolve("Contents/MacOS/NotifyPoint").toString(),
            "--menu-preview", "--settings-file", directory.resolve("settings.json").toString(),
            "--screenshot-session", directory.toString(), scene, appearance,
            Long.toString(ProcessHandle.current().pid()), "-AppleAccentColor", "4"));
        if (hardware) arguments.add("--hardware");
        Process process = new ProcessBuilder(arguments).directory(root.toFile())
            .redirectErrorStream(true).redirectOutput(directory.resolve("preview.log").toFile()).start();
        SESSION.set(new Session(process, directory));
        try {
          Properties state = awaitReady(process, directory);
          if (state.getProperty("status").equals("skipped")) {
            System.out.println("Skipped " + name + ": " + state.getProperty("reason"));
            continue;
          }
          validateState(state, scene, appearance, hardware);
          Path image = directory.resolve(name);
          command(root, Duration.ofSeconds(10), "/usr/sbin/screencapture", "-x", "-t", "png", "-R",
              rectangle(state), image.toString());
          validateImage(image);
          Thread.sleep(150);
          Properties after = readProperties(directory.resolve("state.properties"));
          if (!state.equals(after) || !process.isAlive()) {
            throw new IOException("Menu changed during capture. Before: " + state + "; after: " + after
                + "; preview alive: " + process.isAlive() + "; log: " + directory.resolve("preview.log"));
          }
          staged.put(root.resolve(".github/" + name), image);
          metadata.put(name + ".macOS", osVersion);
          metadata.put(name + ".build", osBuild);
          metadata.put(name + ".strategy", hardware ? "hardware" : "simulated");
          state.forEach((key, value) -> metadata.put(name + "." + key, value.toString()));
          System.out.println("Captured " + name + " (800 x 1040, 2x)");
        } finally {
          stopSession();
        }
      }
    }
    Path stagedMetadata = temporary.resolve("menu-screenshots.properties");
    var text = new StringBuilder("# Generated by make screenshots. Coordinates are screen points.\n");
    metadata.forEach((key, value) -> text.append(key).append('=').append(value).append('\n'));
    Files.writeString(stagedMetadata, text);
    staged.put(metadataFile, stagedMetadata);
    publish(staged, temporary.resolve("backups"));
    deleteTree(temporary.resolve("backups"));
    System.out.println("Updated documentation screenshots in .github/.");
  }

  private static boolean confirmCapture(Path root) throws Exception {
    Process process = new ProcessBuilder("/usr/bin/osascript", "-e", """
        display dialog "NotifyPoint will use your mouse for about 20 seconds to capture documentation screenshots.\n\nPlease avoid moving the mouse or switching applications until capture finishes. Your pointer will be restored afterwards.\n\nA slow or failed capture may take up to two minutes to stop." with title "NotifyPoint screenshots" buttons {"Cancel", "Capture screenshots"} default button "Capture screenshots" cancel button "Cancel" with icon caution
        """).directory(root.toFile()).redirectErrorStream(true).start();
    synchronized (COMMANDS) { COMMANDS.add(process); }
    try {
      if (!process.waitFor(5, TimeUnit.MINUTES)) throw new IOException("Screenshot confirmation timed out.");
      String result = new String(process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
      if (process.exitValue() == 0) return true;
      if (result.contains("(-128)")) return false;
      throw new IOException("Cannot show screenshot confirmation: " + result);
    } finally {
      process.destroyForcibly();
      synchronized (COMMANDS) { COMMANDS.remove(process); }
    }
  }

  private static Properties awaitReady(Process process, Path directory) throws Exception {
    long deadline = System.nanoTime() + Duration.ofSeconds(15).toNanos();
    Properties previous = null;
    int stable = 0;
    String reason = "Menu did not become visible.";
    while (System.nanoTime() < deadline) {
      if (!process.isAlive()) throw new IOException("Preview exited:\n" + Files.readString(directory.resolve("preview.log")));
      Path file = directory.resolve("state.properties");
      if (Files.exists(file)) {
        Properties current = readProperties(file);
        String status = current.getProperty("status", "waiting");
        reason = current.getProperty("reason", reason);
        if (status.equals("error")) throw new IOException(reason);
        if (status.equals("skipped")) return current;
        stable = status.equals("ready") && current.equals(previous) ? stable + 1 : 0;
        previous = current;
        if (stable >= 3) {
          Thread.sleep(300);
          if (current.equals(readProperties(file))) return current;
          stable = 0;
        }
      }
      Thread.sleep(100);
    }
    throw new IOException("Screenshot readiness timed out: " + reason);
  }

  private static void validateState(Properties state, String scene, String appearance, boolean hardware) throws IOException {
    if (!"deadCenter".equals(state.getProperty("position"))
        || !scene.equals(state.getProperty("scene")) || !appearance.equals(state.getProperty("appearance"))
        || !(scene.equals("position") ? "topLeft" : "middleRight").equals(state.getProperty("hover"))
        || !(scene.equals("position") ? "mainDisplay" : "builtInDisplay").equals(state.getProperty("displayTarget"))
        || !"2".equals(state.getProperty("scale"))
        || !"400".equals(state.getProperty("width")) || !"520".equals(state.getProperty("height"))
        || (!hardware && !Boolean.toString(scene.equals("display")).equals(state.getProperty("displaySelector")))) {
      throw new IOException("Unexpected screenshot UI state: " + state);
    }
  }

  private static String rectangle(Properties state) {
    return Integer.parseInt(state.getProperty("x")) + "," + Integer.parseInt(state.getProperty("y")) + ",400,520";
  }

  private static void validateImage(Path path) throws IOException {
    BufferedImage image = ImageIO.read(path.toFile());
    if (image == null || image.getWidth() != 800 || image.getHeight() != 1040) {
      throw new IOException("Expected an 800 x 1040 PNG: " + path);
    }
    int first = image.getRGB(0, 0);
    boolean different = false;
    for (int y = 0; y < image.getHeight() && !different; y += 10) {
      for (int x = 0; x < image.getWidth(); x += 10) {
        if (image.getRGB(x, y) != first) { different = true; break; }
      }
    }
    if (!different) throw new IOException("Screen capture is blank: " + path);
  }

  private static Properties readProperties(Path path) throws IOException {
    Properties result = new Properties();
    try (var reader = Files.newBufferedReader(path)) { result.load(reader); }
    return result;
  }

  private static synchronized void publish(Map<Path, Path> staged, Path backups) throws IOException {
    Files.createDirectories(backups);
    var originals = new LinkedHashMap<Path, Path>();
    var replaced = new ArrayList<Path>();
    for (Path destination : staged.keySet()) {
      Path backup = backups.resolve(destination.getFileName());
      if (Files.exists(destination)) {
        Files.copy(destination, backup);
        originals.put(destination, backup);
      }
    }
    try {
      for (var entry : staged.entrySet()) {
        replaced.add(entry.getKey());
        Files.copy(entry.getValue(), entry.getKey(), java.nio.file.StandardCopyOption.REPLACE_EXISTING);
      }
    } catch (IOException error) {
      for (Path destination : replaced.reversed()) {
        try {
          if (originals.containsKey(destination)) {
            Files.copy(originals.get(destination), destination, java.nio.file.StandardCopyOption.REPLACE_EXISTING);
          } else {
            Files.deleteIfExists(destination);
          }
        } catch (IOException rollback) { error.addSuppressed(rollback); }
      }
      throw error;
    }
  }

  private static String output(Path root, String... arguments) throws Exception {
    Process process = new ProcessBuilder(arguments).directory(root.toFile()).start();
    synchronized (COMMANDS) { COMMANDS.add(process); }
    try {
      if (!process.waitFor(10, TimeUnit.SECONDS) || process.exitValue() != 0) {
        throw new IOException("Command failed: " + String.join(" ", arguments));
      }
      return new String(process.getInputStream().readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
    } finally {
      process.destroyForcibly();
      synchronized (COMMANDS) { COMMANDS.remove(process); }
    }
  }

  private static void command(Path root, Duration timeout, String... arguments) throws Exception {
    Process process = new ProcessBuilder(arguments).directory(root.toFile()).inheritIO().start();
    synchronized (COMMANDS) { COMMANDS.add(process); }
    try {
      if (!process.waitFor(timeout.toMillis(), TimeUnit.MILLISECONDS) || process.exitValue() != 0) {
        throw new IOException("Command failed or timed out: " + String.join(" ", arguments));
      }
    } finally {
      process.descendants().forEach(ProcessHandle::destroyForcibly);
      process.destroyForcibly();
      synchronized (COMMANDS) { COMMANDS.remove(process); }
    }
  }

  private static void stopSession() {
    Session session = SESSION.getAndSet(null);
    if (session == null) return;
    try {
      Files.writeString(session.directory().resolve("stop"), "");
      if (!session.process().waitFor(2, TimeUnit.SECONDS)) {
        session.process().destroy();
        if (!session.process().waitFor(1, TimeUnit.SECONDS)) session.process().destroyForcibly().waitFor();
      }
    } catch (Exception error) {
      session.process().destroyForcibly();
      System.err.println("Preview cleanup: " + error.getMessage());
    }
  }

  // Let publication finish or roll back before an interrupt can end the JVM.
  private static synchronized void cleanup() {
    stopSession();
    synchronized (COMMANDS) {
      for (Process process : COMMANDS) {
        process.descendants().forEach(ProcessHandle::destroyForcibly);
        process.destroyForcibly();
      }
    }
  }

  private static void deleteTree(Path directory) throws IOException {
    try (var paths = Files.walk(directory)) {
      for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) Files.deleteIfExists(path);
    }
  }

  private static void selfTest() throws Exception {
    Path directory = Files.createTempDirectory("NotifyPoint-screenshots-test-");
    try {
      Path original = directory.resolve("original.png");
      Files.writeString(original, "original");
      Path replacement = directory.resolve("replacement.png");
      Files.writeString(replacement, "replacement");
      var staged = new LinkedHashMap<Path, Path>();
      staged.put(original, replacement);
      Path absent = directory.resolve("absent.png");
      staged.put(absent, directory.resolve("missing.png"));
      try {
        publish(staged, directory.resolve("backups"));
        throw new AssertionError("Publication should fail");
      } catch (IOException expected) {
        if (!Files.readString(original).equals("original") || Files.exists(absent)) {
          throw new AssertionError("Failed publication did not restore original assets");
        }
      }
      BufferedImage image = new BufferedImage(800, 1040, BufferedImage.TYPE_INT_RGB);
      ImageIO.write(image, "png", original.toFile());
      try {
        validateImage(original);
        throw new AssertionError("Blank image accepted");
      } catch (IOException expected) { /* Expected rejection. */ }
      image.setRGB(10, 10, 0xffffff);
      ImageIO.write(image, "png", original.toFile());
      validateImage(original);
      Properties state = new Properties();
      state.setProperty("x", "-400");
      state.setProperty("y", "100");
      if (!rectangle(state).equals("-400,100,400,520")) throw new AssertionError("Invalid rectangle");
      state.setProperty("position", "deadCenter");
      state.setProperty("scene", "position");
      state.setProperty("appearance", "light");
      state.setProperty("hover", "topLeft");
      state.setProperty("displayTarget", "mainDisplay");
      state.setProperty("displaySelector", "false");
      state.setProperty("scale", "2");
      state.setProperty("width", "400");
      state.setProperty("height", "520");
      validateState(state, "position", "light", false);
      state.setProperty("hover", "middleRight");
      try {
        validateState(state, "position", "light", false);
        throw new AssertionError("Wrong hover state accepted");
      } catch (IOException expected) { /* Expected rejection. */ }
      System.out.println("Screenshot runner self-checks passed.");
    } finally { deleteTree(directory); }
  }
}
