import 'dart:ui' show Offset;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Result of homography computation
class HomographyMatrixResult {
  /// Matrix4 for Flutter Transform widget
  final Matrix4 matrix;

  /// Four corners of the detected anchor on scene (clockwise from top-left)
  final List<Offset> corners;

  /// Center of anchor on scene
  final Offset center;

  /// Rotation angle (radians, clockwise)
  final double rotation;

  /// Scale factor (1.0 = same size as anchor)
  final double scale;

  /// Number of inliers (good points after RANSAC)
  final int numInliers;

  HomographyMatrixResult({
    required this.matrix,
    required this.corners,
    required this.center,
    required this.rotation,
    required this.scale,
    required this.numInliers,
  });

  @override
  String toString() {
    return 'HomographyMatrixResult(inliers: $numInliers, rotation: $rotation, scale: $scale, center: $center)';
  }
}

/// A pair of matched points between two images
class MatchedPoint {
  /// X coordinate on anchor image
  final double x0;

  /// Y coordinate on anchor image
  final double y0;

  /// X coordinate on scene/camera image
  final double x1;

  /// Y coordinate on scene/camera image
  final double y1;

  const MatchedPoint({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });

  factory MatchedPoint.fromJson(Map<String, dynamic> json) {
    return MatchedPoint(
      x0: (json['x0'] as num).toDouble(),
      y0: (json['y0'] as num).toDouble(),
      x1: (json['x1'] as num).toDouble(),
      y1: (json['y1'] as num).toDouble(),
    );
  }

  @override
  String toString() => 'MatchedPoint(($x0, $y0) -> ($x1, $y1))';
}

