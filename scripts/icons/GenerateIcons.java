// SPDX-License-Identifier: GPL-3.0-only

import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.Line2D;
import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
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
    Path menu = assets.resolve("menu-bar-icon/MenuBarIcon.png");
    Path menu2x = assets.resolve("menu-bar-icon/MenuBarIcon@2x.png");
    Files.createDirectories(icns.getParent());
    Files.createDirectories(menu.getParent());

    writeIcns(source, icns);
    writeMenuIcon(18, menu);
    writeMenuIcon(36, menu2x);
    verify(icns, menu, menu2x);
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

  private static void writeMenuIcon(int size, Path destination) throws IOException {
    int canvasSize = size * 4;
    var canvas = new BufferedImage(canvasSize, canvasSize, BufferedImage.TYPE_INT_ARGB);
    Graphics2D graphics = canvas.createGraphics();
    graphics.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
    graphics.scale(canvasSize / 18.0, canvasSize / 18.0);
    graphics.setColor(Color.BLACK);

    double x = 1.0;
    double y = 3.8;
    double width = 16.0;
    double height = 10.4;
    double cellWidth = width / 3.0;
    double cellHeight = height / 3.0;
    graphics.fill(new RoundRectangle2D.Double(
        x + cellWidth, y + cellHeight, cellWidth, cellHeight, 0.5, 0.5));
    graphics.setStroke(new BasicStroke(1.15f, BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND));
    graphics.draw(new RoundRectangle2D.Double(x, y, width, height, 1.8, 1.8));
    graphics.draw(new Line2D.Double(x + cellWidth, y, x + cellWidth, y + height));
    graphics.draw(new Line2D.Double(x + 2 * cellWidth, y, x + 2 * cellWidth, y + height));
    graphics.draw(new Line2D.Double(x, y + cellHeight, x + width, y + cellHeight));
    graphics.draw(new Line2D.Double(x, y + 2 * cellHeight, x + width, y + 2 * cellHeight));
    graphics.dispose();

    BufferedImage icon = scale(canvas, size);
    if (!ImageIO.write(icon, "png", destination.toFile())) {
      throw new IOException("PNG encoder unavailable");
    }
  }

  private static void verify(Path icns, Path menu, Path menu2x) throws IOException {
    try (var input = new DataInputStream(Files.newInputStream(icns))) {
      if (!"icns".equals(new String(input.readNBytes(4))) || input.readInt() != Files.size(icns)) {
        throw new IOException("invalid ICNS container");
      }
    }
    verifyPng(menu, 18);
    verifyPng(menu2x, 36);
  }

  private static void verifyPng(Path path, int size) throws IOException {
    BufferedImage image = ImageIO.read(path.toFile());
    if (image == null || image.getWidth() != size || image.getHeight() != size) {
      throw new IOException("invalid generated image: " + path);
    }
  }
}
