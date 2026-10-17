// SPDX-License-Identifier: GPL-3.0-only

import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import java.util.HashSet;
import java.util.List;
import javax.imageio.ImageIO;

public class GenerateIcons {
  private static final List<IconChunk> ICNS_CHUNKS = List.of(
      new IconChunk("ic12", 64, false),
      new IconChunk("ic07", 128, false),
      new IconChunk("ic13", 256, false),
      new IconChunk("ic08", 256, false),
      new IconChunk("ic04", 16, true),
      new IconChunk("ic14", 512, false),
      new IconChunk("ic09", 512, false),
      new IconChunk("ic05", 32, true),
      new IconChunk("ic10", 1024, false),
      new IconChunk("ic11", 32, false));

  record IconChunk(String type, int size, boolean legacy) {}

  public static void main(String... args) throws Exception {
    Path root = args.length == 0 ? Path.of("") : Path.of(args[0]);
    if (args.length > 1) {
      throw new IllegalArgumentException("usage: GenerateIcons.java [project-root]");
    }

    Path assets = root.toAbsolutePath().normalize().resolve("src/assets");
    BufferedImage source = ImageIO.read(assets.resolve("icon.png").toFile());
    if (source == null || source.getWidth() != source.getHeight()) {
      throw new IllegalArgumentException("src/assets/icon.png must be a square PNG");
    }

    Path icns = assets.resolve("app-icon/icon.icns");
    Path menu = assets.resolve("menu-bar-icon");
    Files.createDirectories(icns.getParent());
    Files.createDirectories(menu);

    writeIcns(source, icns);
    writeMenuIcons(menu);
    verify(icns);
  }

  private static void writeIcns(BufferedImage source, Path destination) throws IOException {
    var chunks = new ByteArrayOutputStream();
    try (var output = new DataOutputStream(chunks)) {
      for (IconChunk chunk : ICNS_CHUNKS) {
        BufferedImage image = scale(source, chunk.size());
        byte[] data = chunk.legacy() ? encodeArgb(image) : encodePng(image);
        output.writeBytes(chunk.type());
        output.writeInt(data.length + 8);
        output.write(data);
      }
    }

    try (var output = new DataOutputStream(Files.newOutputStream(destination))) {
      output.writeBytes("icns");
      output.writeInt(chunks.size() + 8);
      chunks.writeTo(output);
    }
  }

  private static BufferedImage scale(BufferedImage source, int size) {
    var image = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
    Graphics2D graphics = image.createGraphics();
    graphics.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
    graphics.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
    graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
    graphics.drawImage(source, 0, 0, size, size, null);
    graphics.dispose();
    return image;
  }

  private static byte[] encodePng(BufferedImage image) throws IOException {
    var output = new ByteArrayOutputStream();
    if (!ImageIO.write(image, "png", output)) {
      throw new IOException("PNG encoder unavailable");
    }
    return output.toByteArray();
  }

  private static byte[] encodeArgb(BufferedImage image) throws IOException {
    var output = new ByteArrayOutputStream();
    output.write(new byte[] {'A', 'R', 'G', 'B'});
    int pixelCount = image.getWidth() * image.getHeight();
    for (int shift : new int[] {24, 16, 8, 0}) {
      byte[] channel = new byte[pixelCount];
      for (int y = 0; y < image.getHeight(); y++) {
        for (int x = 0; x < image.getWidth(); x++) {
          channel[y * image.getWidth() + x] = (byte) (image.getRGB(x, y) >>> shift);
        }
      }
      writeRunLengthEncoded(channel, output);
    }
    return output.toByteArray();
  }

  private static void writeRunLengthEncoded(byte[] data, OutputStream output) throws IOException {
    int offset = 0;
    while (offset < data.length) {
      int runLength = runLength(data, offset);
      if (runLength >= 3) {
        output.write(0x80 | (runLength - 3));
        output.write(data[offset] & 0xff);
        offset += runLength;
        continue;
      }

      int literalStart = offset;
      offset += runLength;
      while (offset < data.length && offset - literalStart < 128) {
        runLength = runLength(data, offset);
        if (runLength >= 3) {
          break;
        }
        offset += Math.min(runLength, 128 - (offset - literalStart));
      }
      int literalLength = offset - literalStart;
      output.write(literalLength - 1);
      output.write(data, literalStart, literalLength);
    }
  }

  private static int runLength(byte[] data, int offset) {
    int length = 1;
    while (offset + length < data.length && length < 130 && data[offset + length] == data[offset]) {
      length++;
    }
    return length;
  }

  private static void writeMenuIcons(Path directory) throws IOException, InterruptedException {
    String converter = System.getenv().getOrDefault("RSVG_CONVERT", "rsvg-convert");
    var positions = List.of("topLeft", "topMiddle", "topRight", "middleLeft", "deadCenter",
        "middleRight", "bottomLeft", "bottomMiddle", "bottomRight");
    var distinctImages = new HashSet<String>();
    for (String position : positions) {
      String name = "MenuBarIcon-" + position;
      Path svg = directory.resolve(name + ".svg");
      for (int scale : new int[] {1, 2}) {
        Path png = directory.resolve(name + (scale == 1 ? "" : "@2x") + ".png");
        int width = 24 * scale, height = 22 * scale;
        int exitCode = new ProcessBuilder(converter, "--width=" + width, "--height=" + height,
            "--output=" + png, svg.toString()).inheritIO().start().waitFor();
        if (exitCode != 0) throw new IOException("SVG conversion failed: " + svg);
        verifyPng(png, width, height);
      }
      distinctImages.add(Base64.getEncoder().encodeToString(
          Files.readAllBytes(directory.resolve(name + ".png"))));
    }
    if (distinctImages.size() != positions.size()) throw new IOException("duplicate menu bar positions");
  }

  private static void verify(Path icns) throws IOException {
    try (var input = new DataInputStream(Files.newInputStream(icns))) {
      if (!"icns".equals(new String(input.readNBytes(4))) || input.readInt() != Files.size(icns)) {
        throw new IOException("invalid ICNS container");
      }
    }
  }

  private static void verifyPng(Path path, int width, int height) throws IOException {
    BufferedImage image = ImageIO.read(path.toFile());
    if (image == null || image.getWidth() != width || image.getHeight() != height) {
      throw new IOException("invalid generated image: " + path);
    }
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if ((x == 0 || y == 0 || x == width - 1 || y == height - 1)
            && (image.getRGB(x, y) >>> 24) != 0) {
          throw new IOException("clipped menu bar icon: " + path);
        }
      }
    }
  }
}
