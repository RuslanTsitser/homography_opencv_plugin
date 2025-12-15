import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:ffi/ffi.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import 'homography_result.dart';

/// Native HomographyResult structure
final class _HomographyResultNative extends Struct {
  @Float()
  external double centerX;

  @Float()
  external double centerY;

  @Float()
  external double rotation;

  @Float()
  external double scale;

  @Array(9)
  external Array<Double> homography;

  @Array(8)
  external Array<Float> corners;

  @Int32()
  external int numMatches;

  @Int32()
  external int status;
}

/// FFI function signature for find_homography_from_points
typedef _FindHomographyFromPointsNative = _HomographyResultNative Function(
  Pointer<Float> pts0X,
  Pointer<Float> pts0Y,
  Pointer<Float> pts1X,
  Pointer<Float> pts1Y,
  Int32 numPoints,
  Int32 anchorWidth,
  Int32 anchorHeight,
);

typedef _FindHomographyFromPointsDart = _HomographyResultNative Function(
  Pointer<Float> pts0X,
  Pointer<Float> pts0Y,
  Pointer<Float> pts1X,
  Pointer<Float> pts1Y,
  int numPoints,
  int anchorWidth,
  int anchorHeight,
);

/// FFI function signature for version
typedef _VersionNative = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

/// Singleton class for homography library bindings
class HomographyLib {
  static HomographyLib? _instance;
  DynamicLibrary? _lib;
  _FindHomographyFromPointsDart? _findHomographyFromPoints;
  _VersionDart? _version;
  String? _loadError;

  HomographyLib._() {
    try {
      _lib = _loadLibrary();
      print('[HomographyLib] Library loaded successfully on ${Platform.operatingSystem}');
    } catch (e) {
      _loadError = 'Failed to load library: $e';
      print('[HomographyLib] $_loadError');
      return;
    }

    final lib = _lib;
    if (lib == null) return;

    try {
      _findHomographyFromPoints =
          lib.lookupFunction<_FindHomographyFromPointsNative, _FindHomographyFromPointsDart>(
        'hg_find_homography_from_points',
      );
      print('[HomographyLib] Function hg_find_homography_from_points found');
    } catch (e) {
      _loadError = 'Function hg_find_homography_from_points not found: $e';
      print('[HomographyLib] $_loadError');
    }
    try {
      _version = lib.lookupFunction<_VersionNative, _VersionDart>('hg_lib_version');
      print('[HomographyLib] Function hg_lib_version found, version: ${_version?.call().toDartString()}');
    } catch (e) {
      print('[HomographyLib] Function hg_lib_version not found: $e');
    }
  }

  /// Get load error if any
  String? get loadError => _loadError;

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
  static HomographyLib get instance {
    _instance ??= HomographyLib._();
    return _instance!;
  }

  /// Get library version
  String get version => _version?.call().toDartString() ?? 'unknown';

  /// Check if the native library is available
  bool get isAvailable => _findHomographyFromPoints != null;

  /// Find homography from matched point pairs
  _HomographyResultNative? _findHomographyFromPointsRaw({
    required List<MatchedPoint> matchedPoints,
    required int anchorWidth,
    required int anchorHeight,
  }) {
    final func = _findHomographyFromPoints;
    if (func == null) return null;

    final numPoints = matchedPoints.length;
    if (numPoints < 4) return null;

    final pts0X = malloc<Float>(numPoints);
    final pts0Y = malloc<Float>(numPoints);
    final pts1X = malloc<Float>(numPoints);
    final pts1Y = malloc<Float>(numPoints);

    try {
      for (int i = 0; i < numPoints; i++) {
        final p = matchedPoints[i];
        pts0X[i] = p.x0;
        pts0Y[i] = p.y0;
        pts1X[i] = p.x1;
        pts1Y[i] = p.y1;
      }

      return func(
        pts0X,
        pts0Y,
        pts1X,
        pts1Y,
        numPoints,
        anchorWidth,
        anchorHeight,
      );
    } finally {
      malloc.free(pts0X);
      malloc.free(pts0Y);
      malloc.free(pts1X);
      malloc.free(pts1Y);
    }
  }
}

/// Computes homography matrix from matched points using OpenCV with RANSAC.
///
/// This accounts for perspective transformation (rotation around X, Y, Z axes).
/// Returns null if homography cannot be found or there are not enough points.
///
/// [matchedPoints] - List of matched point pairs (at least 4 required)
/// [anchorSize] - Size of the anchor image in pixels
HomographyMatrixResult? calculateHomographyFromMatchedPoints(
  List<MatchedPoint> matchedPoints,
  Size anchorSize,
) {
  if (matchedPoints.length < 4) return null;

  final lib = HomographyLib.instance;
  print('[HomographyLib] isAvailable: ${lib.isAvailable}, loadError: ${lib.loadError}');
  
  if (!lib.isAvailable) {
    // Fallback to simple similarity transform if library is not available
    print('[HomographyLib] Using fallback (simple similarity transform)');
    return _calculateSimpleSimilarityTransform(matchedPoints);
  }
  
  print('[HomographyLib] Using native OpenCV homography');

  final result = lib._findHomographyFromPointsRaw(
    matchedPoints: matchedPoints,
    anchorWidth: anchorSize.width.toInt(),
    anchorHeight: anchorSize.height.toInt(),
  );

  if (result == null || result.status != 1) return null;

  final matrix = _homographyResultToMatrix4(result);
  if (matrix == null) return null;

  return HomographyMatrixResult(
    matrix: matrix,
    corners: _homographyResultToCorners(result),
    center: Offset(result.centerX, result.centerY),
    rotation: result.rotation,
    scale: result.scale,
    numInliers: result.numMatches,
  );
}

/// Convert native HomographyResult to Flutter Matrix4
Matrix4? _homographyResultToMatrix4(_HomographyResultNative result) {
  if (result.status != 1) return null;

  final h = result.homography;

  // Convert 3x3 homography to 4x4 matrix for Flutter
  // Flutter Matrix4 uses column-major order
  return Matrix4(
    h[0], h[3], 0, h[6],
    h[1], h[4], 0, h[7],
    0, 0, 1, 0,
    h[2], h[5], 0, h[8],
  );
}

/// Convert native HomographyResult corners to list of Offsets
List<Offset> _homographyResultToCorners(_HomographyResultNative result) {
  if (result.status != 1) return [];

  final c = result.corners;
  return [
    Offset(c[0], c[1]),
    Offset(c[2], c[3]),
    Offset(c[4], c[5]),
    Offset(c[6], c[7]),
  ];
}

/// Simple similarity transform (scale + rotation Z + translation)
/// Used as fallback if native library is not available
HomographyMatrixResult? _calculateSimpleSimilarityTransform(List<MatchedPoint> matchedPoints) {
  if (matchedPoints.isEmpty) return null;

  var sumX0 = 0.0, sumY0 = 0.0, sumX1 = 0.0, sumY1 = 0.0;
  for (final point in matchedPoints) {
    sumX0 += point.x0;
    sumY0 += point.y0;
    sumX1 += point.x1;
    sumY1 += point.y1;
  }

  final count = matchedPoints.length.toDouble();
  final meanX0 = sumX0 / count;
  final meanY0 = sumY0 / count;
  final meanX1 = sumX1 / count;
  final meanY1 = sumY1 / count;

  var numeratorReal = 0.0;
  var numeratorImag = 0.0;
  var denominator = 0.0;

  for (final point in matchedPoints) {
    final dx0 = point.x0 - meanX0;
    final dy0 = point.y0 - meanY0;
    final dx1 = point.x1 - meanX1;
    final dy1 = point.y1 - meanY1;

    numeratorReal += dx1 * dx0 + dy1 * dy0;
    numeratorImag += dy1 * dx0 - dx1 * dy0;
    denominator += dx0 * dx0 + dy0 * dy0;
  }

  final scaleRotReal = denominator != 0 ? numeratorReal / denominator : 1.0;
  final scaleRotImag = denominator != 0 ? numeratorImag / denominator : 0.0;

  final tx = meanX1 - (scaleRotReal * meanX0 - scaleRotImag * meanY0);
  final ty = meanY1 - (scaleRotReal * meanY0 + scaleRotImag * meanX0);

  final scale = math.sqrt(scaleRotReal * scaleRotReal + scaleRotImag * scaleRotImag);
  final rotation = scaleRotImag.abs() > 1e-6 || scaleRotReal.abs() > 1e-6
      ? math.atan2(scaleRotImag, scaleRotReal)
      : 0.0;

  final matrix = Matrix4(
    scaleRotReal, scaleRotImag, 0, 0,
    -scaleRotImag, scaleRotReal, 0, 0,
    0, 0, 1, 0,
    tx, ty, 0, 1,
  );

  return HomographyMatrixResult(
    matrix: matrix,
    corners: [],
    center: Offset(meanX1, meanY1),
    rotation: rotation,
    scale: scale,
    numInliers: matchedPoints.length,
  );
}

