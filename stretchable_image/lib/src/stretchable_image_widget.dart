import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class StretchableImage extends StatefulWidget {
  /// Source image.
  final ImageProvider image;

  /// Stretch area ratio, must be less than 1.0. Default is 0.5.
  final double centerStretchAreaRatio;

  /// Target size.
  ///
  /// - If provided, [StretchableImage] will paint with this size exactly.
  /// - If null, the widget will expand to the constraints from its parent
  ///   (using [LayoutBuilder]) and use that as the painting size.
  final Size? size;

  const StretchableImage({
    super.key,
    required this.image,
    this.size,
    this.centerStretchAreaRatio = 0.5,
  }) : assert(centerStretchAreaRatio < 1.0,
            'centerStretchAreaRatio must be less than 1.0');

  @override
  State<StatefulWidget> createState() => _StretchableImageState();
}

class _StretchableImageState extends State<StretchableImage> {
  ui.Image? _image;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  void _resolveImage() {
    _removeStreamListener();

    _imageStream = widget.image.resolve(
      createLocalImageConfiguration(context),
    );

    _imageStreamListener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (!mounted) return;
        setState(() {
          _image = info.image;
        });
      },
      onError: (exception, stackTrace) {
        _removeStreamListener();
        debugPrint('StretchableImage => Failed to load image: $exception');
        if (!mounted) return;
        setState(() {
          _image = null;
        });
      },
    );

    _imageStream!.addListener(_imageStreamListener!);
  }

  void _removeStreamListener() {
    if (_imageStream != null && _imageStreamListener != null) {
      _imageStream!.removeListener(_imageStreamListener!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant StretchableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _removeStreamListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If image not ready, occupy layout space when size is provided,
    // otherwise just return SizedBox.shrink.
    if (_image == null) {
      if (widget.size != null) {
        return SizedBox(
          width: widget.size!.width,
          height: widget.size!.height,
        );
      }
      return const SizedBox.shrink();
    }

    final pixelRatio = MediaQuery.of(context).devicePixelRatio;

    // If user specifies size, use it directly.
    if (widget.size != null) {
      return CustomPaint(
        size: widget.size!,
        painter: _StretchableImagePainter(
          image: _image!,
          pixelRatio: pixelRatio,
          centerStretchAreaRatio: widget.centerStretchAreaRatio,
        ),
      );
    }

    // Otherwise, adapt to parent constraints.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Try to derive a concrete size from constraints.
        final double width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : _image!.width / pixelRatio;
        final double height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : _image!.height / pixelRatio;

        final Size size = Size(width, height);

        return CustomPaint(
          size: size,
          painter: _StretchableImagePainter(
            image: _image!,
            pixelRatio: pixelRatio,
            centerStretchAreaRatio: widget.centerStretchAreaRatio,
          ),
        );
      },
    );
  }
}

/// Custom painter that horizontally stretches a center area of the image.
/// Logic:
///  1. Use the ratio between target height and source height to determine
///     whether we are in stretch or squeeze mode horizontally.
///  2. Horizontally split the image into three parts: [A-H-A].
///     The middle [H] part is the stretchable area, whose width ratio is
///     [centerStretchAreaRatio].
///  3. When widening, only [H] is stretched; [A] on both sides are scaled
///     uniformly without additional distortion.
///  4. When narrowing, [H] is cropped first; [A] parts are kept, only scaled
///     uniformly when [H] is fully removed.
///  5. When [H] width becomes non-positive, the image degenerates to [A-A],
///     and the whole image is uniformly scaled.
class _StretchableImagePainter extends CustomPainter {
  /// Stretch area width ratio, must be less than 1.0.
  final double centerStretchAreaRatio;

  /// Source image.
  final ui.Image image;

  /// Device pixel ratio (dpi).
  final double pixelRatio;

  _StretchableImagePainter({
    required this.image,
    required this.pixelRatio,
    required this.centerStretchAreaRatio,
  }) : assert(centerStretchAreaRatio < 1.0,
            'centerStretchAreaRatio must be less than 1.0');

  @override
  void paint(Canvas canvas, Size size) {
    // Layout in logical coordinates, compute in physical pixels.
    canvas.save();
    canvas.scale(1 / pixelRatio);

    final double targetWidth = size.width * pixelRatio;
    final double targetHeight = size.height * pixelRatio;

    final double imageWidth = image.width.toDouble();
    final double imageHeight = image.height.toDouble();

    final paint = Paint()..isAntiAlias = true;

    _paintHorizontalCustomCenterSlice(
      canvas,
      paint,
      imageWidth,
      imageHeight,
      targetWidth,
      targetHeight,
    );
    canvas.restore();
  }

  void _paintHorizontalCustomCenterSlice(
    Canvas canvas,
    Paint paint,
    double sW, // source width
    double sH, // source height
    double tW, // target width
    double tH, // target height
  ) {
    if (sW <= 0 ||
        sH <= 0 ||
        tW <= 0 ||
        tH <= 0 ||
        centerStretchAreaRatio >= 1.0) {
      return;
    }

    // Ratio by height: under this, we decide stretch/squeeze horizontally.
    final double kh = tH / sH;

    // Horizontal split into three parts: [left - center - right].
    final double leftWidth = sW * ((1 - centerStretchAreaRatio) / 2);
    final double centerWidth = sW * centerStretchAreaRatio;
    final double rightWidth = sW * ((1 - centerStretchAreaRatio) / 2);

    // Scaled widths in physical pixels.
    final double scaledLeftWidth = leftWidth * kh;
    final double scaledCenterWidth = centerWidth * kh;
    final double scaledRightWidth = rightWidth * kh;

    // Natural total width under uniform scaling.
    final double naturalWidth =
        (leftWidth + centerWidth + rightWidth) * kh; // Ws * kh

    // Minimal width with center completely removed.
    final double minWidthWithNoCenter = scaledLeftWidth + scaledRightWidth;

    // Helper: draw only left & right parts.
    void drawOnlySides() {
      final Rect srcLeft = Rect.fromLTWH(0, 0, leftWidth, sH);
      final Rect srcRight = Rect.fromLTWH(
        leftWidth + centerWidth,
        0,
        rightWidth,
        sH,
      );

      final Rect dstLeft = Rect.fromLTWH(0, 0, scaledLeftWidth, tH);
      final Rect dstRight = Rect.fromLTWH(
        scaledLeftWidth,
        0,
        scaledRightWidth,
        tH,
      );

      canvas.drawImageRect(image, srcLeft, dstLeft, paint);
      canvas.drawImageRect(image, srcRight, dstRight, paint);
    }

    if (tW >= naturalWidth) {
      // ========= Region A: stretch horizontally (A scaled, H stretched) =========
      final double extra = tW - naturalWidth;

      final double dstLeftWidth = scaledLeftWidth;
      final double dstCenterWidth = scaledCenterWidth + extra;
      final double dstRightWidth = scaledRightWidth;

      // Source rects.
      final Rect srcLeft = Rect.fromLTWH(0, 0, leftWidth, sH);
      final Rect srcCenter = Rect.fromLTWH(leftWidth, 0, centerWidth, sH);
      final Rect srcRight = Rect.fromLTWH(
        leftWidth + centerWidth,
        0,
        rightWidth,
        sH,
      );

      // Destination rects.
      final Rect dstLeft = Rect.fromLTWH(0, 0, dstLeftWidth, tH);
      final Rect dstCenter = Rect.fromLTWH(dstLeftWidth, 0, dstCenterWidth, tH);
      final Rect dstRight = Rect.fromLTWH(
        dstLeftWidth + dstCenterWidth,
        0,
        dstRightWidth,
        tH,
      );

      canvas.drawImageRect(image, srcLeft, dstLeft, paint);
      canvas.drawImageRect(image, srcCenter, dstCenter, paint);
      canvas.drawImageRect(image, srcRight, dstRight, paint);
    } else if (tW >= minWidthWithNoCenter) {
      // ========= Region B: crop center only (A kept, H partially visible) =========

      // Available center width in target pixels.
      final double availableCenterWidth =
          tW - scaledLeftWidth - scaledRightWidth;
      // availableCenterWidth ∈ [0, scaledCenterWidth]
      final double dstCenterWidth = availableCenterWidth.clamp(
        0.0,
        scaledCenterWidth,
      );

      // Width of center area that is cut (in target coordinates).
      final double cutDst = scaledCenterWidth - dstCenterWidth;
      // Convert back to source coordinates.
      final double cutSrc = cutDst / kh;

      // Width to keep from each side in the center area (source).
      double halfKeepSrc = (centerWidth - cutSrc) / 2.0;
      halfKeepSrc = halfKeepSrc.clamp(0.0, centerWidth / 2.0);

      if (dstCenterWidth <= 0.0 || halfKeepSrc <= 0.0) {
        drawOnlySides();
        return;
      }

      // ===== Source rects (in source pixels) =====

      // Left fixed region.
      final Rect srcLeft = Rect.fromLTWH(0, 0, leftWidth, sH);

      // Left half of center region.
      final double srcCenterLeftX = leftWidth;
      final Rect srcCenterLeft = Rect.fromLTWH(
        srcCenterLeftX,
        0,
        halfKeepSrc,
        sH,
      );

      // Right half of center region.
      final double srcCenterRightX = leftWidth + centerWidth - halfKeepSrc;
      final Rect srcCenterRight = Rect.fromLTWH(
        srcCenterRightX,
        0,
        halfKeepSrc,
        sH,
      );

      // Right fixed region.
      final Rect srcRight = Rect.fromLTWH(
        leftWidth + centerWidth,
        0,
        rightWidth,
        sH,
      );

      // ===== Destination rects (in target pixels) =====

      // Left fixed region.
      final Rect dstLeft = Rect.fromLTWH(0, 0, scaledLeftWidth, tH);

      // Center region split into two halves.
      final double dstCenterHalfWidth = dstCenterWidth / 2.0;

      final Rect dstCenterLeft = Rect.fromLTWH(
        scaledLeftWidth,
        0,
        dstCenterHalfWidth,
        tH,
      );

      final Rect dstCenterRight = Rect.fromLTWH(
        scaledLeftWidth + dstCenterHalfWidth,
        0,
        dstCenterHalfWidth,
        tH,
      );

      // Right fixed region after the whole center.
      final Rect dstRight = Rect.fromLTWH(
        scaledLeftWidth + dstCenterWidth,
        0,
        scaledRightWidth,
        tH,
      );

      // ===== Actual draw =====
      canvas.drawImageRect(image, srcLeft, dstLeft, paint);
      canvas.drawImageRect(image, srcCenterLeft, dstCenterLeft, paint);
      canvas.drawImageRect(image, srcCenterRight, dstCenterRight, paint);
      canvas.drawImageRect(image, srcRight, dstRight, paint);
    } else {
      // ========= Region C: center fully gone, A-A uniformly scaled down =========

      // Second-stage scale ratio (0~1).
      final double kw = tW / minWidthWithNoCenter;

      // Final height after second-stage scale.
      final double finalHeight = tH * kw;

      // Final left/right widths.
      final double finalLeftWidth = scaledLeftWidth * kw;
      final double finalRightWidth = scaledRightWidth * kw;

      // Source rects (still use original A-A parts).
      final Rect srcLeft = Rect.fromLTWH(0, 0, leftWidth, sH);
      final Rect srcRight = Rect.fromLTWH(
        leftWidth + centerWidth,
        0,
        rightWidth,
        sH,
      );

      // Vertically center the final image (optional).
      final double offsetY = (tH - finalHeight) / 2.0;

      // Destination rects.
      final Rect dstLeft = Rect.fromLTWH(
        0,
        offsetY,
        finalLeftWidth,
        finalHeight,
      );
      final Rect dstRight = Rect.fromLTWH(
        finalLeftWidth,
        offsetY,
        finalRightWidth,
        finalHeight,
      );

      canvas.drawImageRect(image, srcLeft, dstLeft, paint);
      canvas.drawImageRect(image, srcRight, dstRight, paint);
      // Center region width is 0, skip drawing.
    }
  }

  @override
  bool shouldRepaint(covariant _StretchableImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.pixelRatio != pixelRatio ||
        oldDelegate.centerStretchAreaRatio != centerStretchAreaRatio;
  }
}
