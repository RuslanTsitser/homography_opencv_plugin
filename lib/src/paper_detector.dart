import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import 'paper_detection_result.dart';

// ============================================================================
// Native structures
// ============================================================================

/// Native PaperDetectionResult structure
final class _PaperDetectionResultNative extends Struct {
  @Array(8)
  external Array<Float> corners;

  @Float()
  external double centerX;

  @Float()
  external double centerY;

  @Array(9)
  external Array<Double> homography;

  @Array(3)
  external Array<Double> rvec;

  @Array(3)
  external Array<Double> tvec;

  @Float()
  external double area;

  @Float()
  external double perimeter;

  @Float()
  external double aspectRatio;

  @Int32()
  external int status;
}

/// Native PaperDetectionConfig structure
final class _PaperDetectionConfigNative extends Struct {
  @Int32()
  external int cannyThreshold1;

  @Int32()
  external int cannyThreshold2;

  @Int32()
  external int blurKernelSize;

  @Float()
  external double minAreaRatio;

  @Float()
  external double maxAreaRatio;

  @Float()
  external double expectedAspectRatio;

  @Float()
  external double aspectRatioTolerance;

  @Float()
  external double paperWidthMm;

  @Float()
  external double paperHeightMm;

  @Float()
  external double focalLength;

  @Float()
  external double cx;

  @Float()
  external double cy;
}

// ============================================================================
// FFI function signatures
// ============================================================================

typedef _DetectPaperNative =
    _PaperDetectionResultNative Function(
      Pointer<Uint8> imageData,
      Int32 imageWidth,
      Int32 imageHeight,
      Int32 imageChannels,
      Pointer<_PaperDetectionConfigNative> config,
    );

typedef _DetectPaperDart =
    _PaperDetectionResultNative Function(
      Pointer<Uint8> imageData,
      int imageWidth,
      int imageHeight,
      int imageChannels,
      Pointer<_PaperDetectionConfigNative> config,
    );

typedef _DetectPaperEncodedNative =
    _PaperDetectionResultNative Function(
      Pointer<Uint8> imageBytes,
      Size imageSize,
      Pointer<_PaperDetectionConfigNative> config,
    );

typedef _DetectPaperEncodedDart =
    _PaperDetectionResultNative Function(
      Pointer<Uint8> imageBytes,
      int imageSize,
      Pointer<_PaperDetectionConfigNative> config,
    );

// ============================================================================
// Paper Detector
// ============================================================================

/// Paper/document detector using contour-based detection
///
/// This class provides methods to detect rectangular paper-like objects
/// in images using edge detection and contour analysis.
class PaperDetector {
  static PaperDetector? _instance;
  DynamicLibrary? _lib;
  _DetectPaperDart? _detectPaper;
  _DetectPaperEncodedDart? _detectPaperEncoded;
  String? _loadError;

  PaperDetector._() {
    try {
      _lib = _loadLibrary();
      print('[PaperDetector] Library loaded successfully on ${Platform.operatingSystem}');
    } catch (e) {
      _loadError = 'Failed to load library: $e';
      print('[PaperDetector] $_loadError');
      return;
    }

    final lib = _lib;
    if (lib == null) return;

    try {
      _detectPaper = lib.lookupFunction<_DetectPaperNative, _DetectPaperDart>('hg_detect_paper');
      print('[PaperDetector] Function hg_detect_paper found');
    } catch (e) {
      _loadError = 'Function hg_detect_paper not found: $e';
      print('[PaperDetector] $_loadError');
    }

    try {
      _detectPaperEncoded = lib.lookupFunction<_DetectPaperEncodedNative, _DetectPaperEncodedDart>(
        'hg_detect_paper_encoded',
      );
      print('[PaperDetector] Function hg_detect_paper_encoded found');
    } catch (e) {
      print('[PaperDetector] Function hg_detect_paper_encoded not found: $e');
    }
  }

  static DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libhomography.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.executable();
    } else if (Platform.isMacOS) {
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('homography.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libhomography.so');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  /// Get the singleton instance
  static PaperDetector get instance {
    _instance ??= PaperDetector._();
    return _instance!;
  }

  /// Get load error if any
  String? get loadError => _loadError;

  /// Check if the native library is available
  bool get isAvailable => _detectPaper != null;

  /// Detect paper in raw image data
  ///
  /// [imageData] - Raw pixel data (RGB, RGBA, or grayscale)
  /// [width] - Image width in pixels
  /// [height] - Image height in pixels
  /// [channels] - Number of channels (1, 3, or 4)
  /// [config] - Detection configuration (optional)
  ///
  /// Returns [PaperDetectionResult] with detection results
  PaperDetectionResult detectPaper({
    required Uint8List imageData,
    required int width,
    required int height,
    required int channels,
    PaperDetectionConfig? config,
  }) {
    final func = _detectPaper;
    if (func == null) {
      print('[PaperDetector] Native function not available');
      return PaperDetectionResult.invalid();
    }

    final imagePtr = malloc<Uint8>(imageData.length);
    Pointer<_PaperDetectionConfigNative>? configPtr;

    try {
      // Copy image data
      for (int i = 0; i < imageData.length; i++) {
        imagePtr[i] = imageData[i];
      }

      // Create config if provided
      if (config != null) {
        configPtr = malloc<_PaperDetectionConfigNative>();
        _fillConfigNative(configPtr.ref, config);
      }

      final result = func(imagePtr, width, height, channels, configPtr ?? nullptr);

      return _convertResult(result, config?.focalLength ?? 0);
    } finally {
      malloc.free(imagePtr);
      if (configPtr != null) {
        malloc.free(configPtr);
      }
    }
  }

  /// Detect paper in encoded image (JPEG/PNG)
  ///
  /// [imageBytes] - Encoded image bytes
  /// [config] - Detection configuration (optional)
  ///
  /// Returns [PaperDetectionResult] with detection results
  PaperDetectionResult detectPaperEncoded({required Uint8List imageBytes, PaperDetectionConfig? config}) {
    final func = _detectPaperEncoded;
    if (func == null) {
      print('[PaperDetector] Native function not available');
      return PaperDetectionResult.invalid();
    }

    final imagePtr = malloc<Uint8>(imageBytes.length);
    Pointer<_PaperDetectionConfigNative>? configPtr;

    try {
      // Copy image data
      for (int i = 0; i < imageBytes.length; i++) {
        imagePtr[i] = imageBytes[i];
      }

      // Create config if provided
      if (config != null) {
        configPtr = malloc<_PaperDetectionConfigNative>();
        _fillConfigNative(configPtr.ref, config);
      }

      final result = func(imagePtr, imageBytes.length, configPtr ?? nullptr);

      return _convertResult(result, config?.focalLength ?? 0);
    } finally {
      malloc.free(imagePtr);
      if (configPtr != null) {
        malloc.free(configPtr);
      }
    }
  }

  void _fillConfigNative(_PaperDetectionConfigNative native, PaperDetectionConfig config) {
    native.cannyThreshold1 = config.cannyThreshold1;
    native.cannyThreshold2 = config.cannyThreshold2;
    native.blurKernelSize = config.blurKernelSize;
    native.minAreaRatio = config.minAreaRatio;
    native.maxAreaRatio = config.maxAreaRatio;
    native.expectedAspectRatio = config.expectedAspectRatio;
    native.aspectRatioTolerance = config.aspectRatioTolerance;
    native.paperWidthMm = config.paperWidthMm;
    native.paperHeightMm = config.paperHeightMm;
    native.focalLength = config.focalLength;
    native.cx = config.cx;
    native.cy = config.cy;
  }

  PaperDetectionResult _convertResult(_PaperDetectionResultNative native, double focalLength) {
    if (native.status != 1) {
      return PaperDetectionResult.invalid();
    }

    // Extract corners
    final corners = <Offset>[];
    for (int i = 0; i < 4; i++) {
      corners.add(Offset(native.corners[i * 2], native.corners[i * 2 + 1]));
    }

    // Extract homography matrix (convert 3x3 to 4x4)
    final h = native.homography;
    final homography = Matrix4(h[0], h[3], 0, h[6], h[1], h[4], 0, h[7], 0, 0, 1, 0, h[2], h[5], 0, h[8]);

    // Extract pose vectors if available
    Vector3? rotationVector;
    Vector3? translationVector;
    if (focalLength > 0) {
      rotationVector = Vector3(native.rvec[0], native.rvec[1], native.rvec[2]);
      translationVector = Vector3(native.tvec[0], native.tvec[1], native.tvec[2]);
    }

    return PaperDetectionResult(
      corners: corners,
      center: Offset(native.centerX, native.centerY),
      homography: homography,
      rotationVector: rotationVector,
      translationVector: translationVector,
      area: native.area,
      perimeter: native.perimeter,
      aspectRatio: native.aspectRatio,
      isValid: true,
    );
  }
}

/// Convenience function to detect paper in raw image data
///
/// Uses [PaperDetector.instance] singleton
PaperDetectionResult detectPaper({
  required Uint8List imageData,
  required int width,
  required int height,
  required int channels,
  PaperDetectionConfig? config,
}) {
  return PaperDetector.instance.detectPaper(
    imageData: imageData,
    width: width,
    height: height,
    channels: channels,
    config: config,
  );
}

/// Convenience function to detect paper in encoded image
///
/// Uses [PaperDetector.instance] singleton
PaperDetectionResult detectPaperEncoded({required Uint8List imageBytes, PaperDetectionConfig? config}) {
  return PaperDetector.instance.detectPaperEncoded(imageBytes: imageBytes, config: config);
}
