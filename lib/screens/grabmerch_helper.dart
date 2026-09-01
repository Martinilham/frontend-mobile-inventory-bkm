import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ImageProcessingArgs {
  final Uint8List bytes;
  final int removeBgStrength;
  final bool autoRemoveBg;
  final bool mengandungBabi;
  final String logoKey;
  final String logoLayer;
  final int logoOpacity;
  final int logoSize;
  final int logoOffsetY;
  final String labelLayer;
  final int labelOpacity;
  final int labelSize;
  final int labelOffsetX;
  final int labelOffsetY;
  final int productZoom;
  final int productRotate;
  final int productOffsetX;
  final int productOffsetY;
  final Uint8List? logoBytes;
  final Uint8List? labelBytes;

  const ImageProcessingArgs({
    required this.bytes,
    required this.removeBgStrength,
    this.autoRemoveBg = true,
    this.mengandungBabi = false,
    this.logoKey = 'blok_m',
    this.logoLayer = 'front',
    this.logoOpacity = 46,
    this.logoSize = 82,
    this.logoOffsetY = 12,
    this.labelLayer = 'front',
    this.labelOpacity = 68,
    this.labelSize = 26,
    this.labelOffsetX = 10,
    this.labelOffsetY = 8,
    this.productZoom = 100,
    this.productRotate = 0,
    this.productOffsetX = 0,
    this.productOffsetY = 5,
    this.logoBytes,
    this.labelBytes,
  });
}

const int _canvasSize = 1080;

Uint8List processImageBytes(ImageProcessingArgs args) {
  final source = img.decodeImage(args.bytes);
  if (source == null) {
    throw Exception('Gagal memproses gambar');
  }

  final product = args.autoRemoveBg
      ? _removeBackground(source, args.removeBgStrength)
      : _ensureRgba(source);
  final canvas = img.Image(width: _canvasSize, height: _canvasSize);
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));

  final logo = args.logoBytes != null ? _prepareOverlay(args.logoBytes!) : null;
  final label = args.labelBytes != null ? _prepareOverlay(args.labelBytes!) : null;

  final placedProduct = _transformProduct(
    product,
    zoom: args.productZoom,
    rotate: args.productRotate,
    offsetX: args.productOffsetX,
    offsetY: args.productOffsetY,
  );

  if (args.logoLayer == 'back' && logo != null) {
    _drawLogo(canvas, logo, args.logoOpacity, args.logoSize, args.logoOffsetY);
  }
  if (args.mengandungBabi && args.labelLayer == 'back' && label != null) {
    _drawLabel(canvas, label, args.labelOpacity, args.labelSize, args.labelOffsetX, args.labelOffsetY);
  }

  _compositeOntoCanvas(canvas, placedProduct);

  if (args.logoLayer == 'front' && logo != null) {
    _drawLogo(canvas, logo, args.logoOpacity, args.logoSize, args.logoOffsetY);
  }
  if (args.mengandungBabi && args.labelLayer == 'front' && label != null) {
    _drawLabel(canvas, label, args.labelOpacity, args.labelSize, args.labelOffsetX, args.labelOffsetY);
  }

  _flattenAlphaToWhite(canvas);
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 92));
}

img.Image _prepareOverlay(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw Exception('Gagal memuat overlay');
  }
  final output = img.Image.from(image);
  _removeDarkBackground(output);
  return output;
}

void _removeDarkBackground(img.Image image, {int threshold = 40}) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      if (r <= threshold && g <= threshold && b <= threshold) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
}

img.Image _ensureRgba(img.Image image) {
  final output = img.Image.from(image);
  for (var y = 0; y < output.height; y++) {
    for (var x = 0; x < output.width; x++) {
      final pixel = output.getPixel(x, y);
      if (pixel.a.toInt() < 255) continue;
      output.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, pixel.a);
    }
  }
  return output;
}

img.Image _removeBackground(img.Image image, int strength) {
  final bgColor = _estimateBackgroundColor(image);
  final output = img.Image.from(image);
  // Semakin tinggi strength, semakin agresif
  final cutoff = 25 + (100 - strength.clamp(0, 100)) * 2.2;
  const feather = 22.0;

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      final distance = sqrt(
        (r - bgColor[0]) * (r - bgColor[0]) +
            (g - bgColor[1]) * (g - bgColor[1]) +
            (b - bgColor[2]) * (b - bgColor[2]),
      );
      final brightness = (r + g + b) / 3;

      int alpha;
      if (distance <= cutoff - feather) {
        // Hapus pixel yang mirip warna background (terang maupun gelap di tepi)
        alpha = brightness > 90 ? 0 : 255;
      } else if (distance >= cutoff + feather) {
        alpha = 255;
      } else {
        final t = (distance - (cutoff - feather)) / (feather * 2);
        alpha = (t * 255).round().clamp(0, 255);
      }

      output.setPixelRgba(x, y, r, g, b, alpha);
    }
  }

  return output;
}

img.Image _transformProduct(
  img.Image product, {
  required int zoom,
  required int rotate,
  required int offsetX,
  required int offsetY,
}) {
  final fitScale = min(
    (_canvasSize * 0.72) / product.width,
    (_canvasSize * 0.72) / product.height,
  );
  final zoomScale = fitScale * (zoom / 100);
  final targetWidth = max(1, (product.width * zoomScale).round());
  final targetHeight = max(1, (product.height * zoomScale).round());

  var transformed = img.copyResize(product, width: targetWidth, height: targetHeight);
  if (rotate != 0) {
    transformed = img.copyRotate(transformed, angle: rotate.toDouble());
  }

  final dx = ((_canvasSize - transformed.width) / 2 + (_canvasSize * offsetX / 100)).round();
  final dy = ((_canvasSize - transformed.height) / 2 + (_canvasSize * offsetY / 100)).round();

  final layer = img.Image(width: _canvasSize, height: _canvasSize);
  img.fill(layer, color: img.ColorRgba8(255, 255, 255, 0));
  _compositeOntoCanvas(layer, transformed, dstX: dx, dstY: dy);
  return layer;
}

void _compositeOntoCanvas(img.Image canvas, img.Image layer, {int dstX = 0, int dstY = 0}) {
  for (var y = 0; y < layer.height; y++) {
    for (var x = 0; x < layer.width; x++) {
      final src = layer.getPixel(x, y);
      final alpha = src.a / 255.0;
      if (alpha <= 0) continue;

      final dstXPos = x + dstX;
      final dstYPos = y + dstY;
      if (dstXPos < 0 || dstYPos < 0 || dstXPos >= canvas.width || dstYPos >= canvas.height) {
        continue;
      }

      final dst = canvas.getPixel(dstXPos, dstYPos);
      final outR = (src.r * alpha + dst.r * (1 - alpha)).round();
      final outG = (src.g * alpha + dst.g * (1 - alpha)).round();
      final outB = (src.b * alpha + dst.b * (1 - alpha)).round();
      canvas.setPixelRgba(dstXPos, dstYPos, outR, outG, outB, 255);
    }
  }
}

void _drawLogo(img.Image canvas, img.Image logo, int opacity, int size, int offsetY) {
  final targetWidth = (_canvasSize * (size / 100)).round();
  final targetHeight = (logo.height * targetWidth / logo.width).round();
  final resized = img.copyResize(logo, width: targetWidth, height: targetHeight);
  final tinted = _applyOpacity(resized, opacity);
  final x = ((_canvasSize - targetWidth) / 2).round();
  final y = (_canvasSize - targetHeight - (_canvasSize * offsetY / 100)).round();
  _compositeOntoCanvas(canvas, tinted, dstX: x, dstY: y);
}

void _drawLabel(
  img.Image canvas,
  img.Image label,
  int opacity,
  int size,
  int offsetX,
  int offsetY,
) {
  final targetWidth = (_canvasSize * (size / 100)).round();
  final targetHeight = (label.height * targetWidth / label.width).round();
  final resized = img.copyResize(label, width: targetWidth, height: targetHeight);
  final tinted = _applyOpacity(resized, opacity);
  final x = (_canvasSize * offsetX / 100).round();
  final y = (_canvasSize * offsetY / 100).round();
  _compositeOntoCanvas(canvas, tinted, dstX: x, dstY: y);
}

img.Image _applyOpacity(img.Image image, int alphaPercent) {
  final output = img.Image.from(image);
  final factor = (alphaPercent / 100).clamp(0.0, 1.0);
  for (var y = 0; y < output.height; y++) {
    for (var x = 0; x < output.width; x++) {
      final pixel = output.getPixel(x, y);
      final currentAlpha = pixel.a.toInt();
      if (currentAlpha == 0) continue;
      final mergedAlpha = (currentAlpha * factor).round().clamp(0, 255);
      output.setPixelRgba(x, y, pixel.r, pixel.g, pixel.b, mergedAlpha);
    }
  }
  return output;
}

void _flattenAlphaToWhite(img.Image image) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final alpha = pixel.a / 255.0;
      if (alpha >= 1) continue;
      final r = (pixel.r * alpha + 255 * (1 - alpha)).round();
      final g = (pixel.g * alpha + 255 * (1 - alpha)).round();
      final b = (pixel.b * alpha + 255 * (1 - alpha)).round();
      image.setPixelRgba(x, y, r, g, b, 255);
    }
  }
}

List<int> _estimateBackgroundColor(img.Image image) {
  final pixels = <List<int>>[];
  final cornerSize = max(8, min(image.width, image.height) ~/ 10);

  void sampleCorner(int startX, int startY) {
    for (var y = startY; y < startY + cornerSize && y < image.height; y++) {
      for (var x = startX; x < startX + cornerSize && x < image.width; x++) {
        pixels.add(_pixelToRgb(image.getPixel(x, y)));
      }
    }
  }

  sampleCorner(0, 0);
  sampleCorner(max(0, image.width - cornerSize), 0);
  sampleCorner(0, max(0, image.height - cornerSize));
  sampleCorner(max(0, image.width - cornerSize), max(0, image.height - cornerSize));

  if (pixels.isEmpty) return [255, 255, 255];

  final sum = pixels.fold<List<int>>([0, 0, 0], (acc, rgb) {
    acc[0] += rgb[0];
    acc[1] += rgb[1];
    acc[2] += rgb[2];
    return acc;
  });

  return [
    (sum[0] ~/ pixels.length).clamp(0, 255),
    (sum[1] ~/ pixels.length).clamp(0, 255),
    (sum[2] ~/ pixels.length).clamp(0, 255),
  ];
}

List<int> _pixelToRgb(dynamic pixel) {
  return [pixel.r, pixel.g, pixel.b];
}
