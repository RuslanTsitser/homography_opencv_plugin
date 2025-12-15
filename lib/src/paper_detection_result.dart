import 'dart:ui' show Offset;

import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

/// Result of paper/document detection
class PaperDetectionResult {
  /// Four corners of the detected paper in image coordinates (clockwise from top-left)
  final List<Offset> corners;

  /// Center of the detected paper
  final Offset center;

  /// 3x3 homography matrix that transforms from canonical paper coordinates to image coordinates
  final Matrix4 homography;

  /// Camera pose: rotation vector (Rodrigues representation)
  final Vector3? rotationVector;

  /// Camera pose: translation vector
  final Vector3? translationVector;

  /// Contour area in pixels
  final double area;

  /// Contour perimeter in pixels
  final double perimeter;

  /// Aspect ratio of the detected rectangle (width/height, always <= 1)
  final double aspectRatio;

  /// Whether the detection was successful
  final bool isValid;

  PaperDetectionResult({
    required this.corners,
    required this.center,
    required this.homography,
    this.rotationVector,
    this.translationVector,
    required this.area,
    required this.perimeter,
    required this.aspectRatio,
    required this.isValid,
  });

  /// Create a failed/invalid result
  factory PaperDetectionResult.invalid() {
    return PaperDetectionResult(
      corners: [],
      center: Offset.zero,
      homography: Matrix4.identity(),
      area: 0,
      perimeter: 0,
      aspectRatio: 0,
      isValid: false,
    );
  }

  /// Whether camera pose is available
  bool get hasPose => rotationVector != null && translationVector != null;

  /// Get the width of the detected paper (average of top and bottom edges)
  double get width {
    if (corners.length != 4) return 0;
    final topEdge = (corners[1] - corners[0]).distance;
    final bottomEdge = (corners[2] - corners[3]).distance;
    return (topEdge + bottomEdge) / 2;
  }

  /// Get the height of the detected paper (average of left and right edges)
  double get height {
    if (corners.length != 4) return 0;
    final leftEdge = (corners[3] - corners[0]).distance;
    final rightEdge = (corners[2] - corners[1]).distance;
    return (leftEdge + rightEdge) / 2;
  }

  @override
  String toString() {
    if (!isValid) return 'PaperDetectionResult(invalid)';
    return 'PaperDetectionResult('
        'center: $center, '
        'area: ${area.toStringAsFixed(0)}, '
        'aspectRatio: ${aspectRatio.toStringAsFixed(3)}, '
        'hasPose: $hasPose)';
  }
}

/// Configuration for paper detection
class PaperDetectionConfig {
  /// Canny edge detection lower threshold
  final int cannyThreshold1;

  /// Canny edge detection upper threshold
  final int cannyThreshold2;

  /// Gaussian blur kernel size (must be odd, 0 to disable)
  final int blurKernelSize;

  /// Minimum area ratio (detected area / image area)
  final double minAreaRatio;

  /// Maximum area ratio
  final double maxAreaRatio;

  /// Expected aspect ratio of the paper (width/height, e.g., A4 ≈ 0.707)
  final double expectedAspectRatio;

  /// Tolerance for aspect ratio matching (0.3 = 30% deviation allowed)
  final double aspectRatioTolerance;

  /// Paper physical width in mm (for pose estimation)
  final double paperWidthMm;

  /// Paper physical height in mm (for pose estimation)
  final double paperHeightMm;

  /// Camera focal length in pixels (0 to skip pose estimation)
  final double focalLength;

  /// Camera principal point X
  final double cx;

  /// Camera principal point Y
  final double cy;

  const PaperDetectionConfig({
    this.cannyThreshold1 = 50,
    this.cannyThreshold2 = 150,
    this.blurKernelSize = 5,
    this.minAreaRatio = 0.05,
    this.maxAreaRatio = 0.95,
    this.expectedAspectRatio = 0.707, // A4: 210/297
    this.aspectRatioTolerance = 0.3,
    this.paperWidthMm = 210, // A4
    this.paperHeightMm = 297, // A4
    this.focalLength = 0, // Skip pose by default
    this.cx = 0,
    this.cy = 0,
  });

  // ============================================================================
  // ISO A-series paper presets (portrait orientation)
  // ============================================================================

  /// A0 paper (841 × 1189 mm)
  static const a0Portrait = PaperDetectionConfig(
    expectedAspectRatio: 841 / 1189, // ~0.707
    paperWidthMm: 841,
    paperHeightMm: 1189,
  );

  /// A1 paper (594 × 841 mm)
  static const a1Portrait = PaperDetectionConfig(
    expectedAspectRatio: 594 / 841, // ~0.707
    paperWidthMm: 594,
    paperHeightMm: 841,
  );

  /// A2 paper (420 × 594 mm)
  static const a2Portrait = PaperDetectionConfig(
    expectedAspectRatio: 420 / 594, // ~0.707
    paperWidthMm: 420,
    paperHeightMm: 594,
  );

  /// A3 paper (297 × 420 mm)
  static const a3Portrait = PaperDetectionConfig(
    expectedAspectRatio: 297 / 420, // ~0.707
    paperWidthMm: 297,
    paperHeightMm: 420,
  );

  /// A4 paper (210 × 297 mm) - default
  static const a4Portrait = PaperDetectionConfig();

  /// A5 paper (148 × 210 mm)
  static const a5Portrait = PaperDetectionConfig(
    expectedAspectRatio: 148 / 210, // ~0.705
    paperWidthMm: 148,
    paperHeightMm: 210,
  );

  /// A6 paper (105 × 148 mm)
  static const a6Portrait = PaperDetectionConfig(
    expectedAspectRatio: 105 / 148, // ~0.709
    paperWidthMm: 105,
    paperHeightMm: 148,
  );

  // ============================================================================
  // ISO A-series paper presets (landscape orientation)
  // ============================================================================

  /// A3 paper landscape (420 × 297 mm)
  static const a3Landscape = PaperDetectionConfig(
    expectedAspectRatio: 297 / 420, // still use portrait ratio for detection
    paperWidthMm: 420,
    paperHeightMm: 297,
  );

  /// A4 paper landscape (297 × 210 mm)
  static const a4Landscape = PaperDetectionConfig(
    expectedAspectRatio: 210 / 297, // ~0.707
    paperWidthMm: 297,
    paperHeightMm: 210,
  );

  /// A5 paper landscape (210 × 148 mm)
  static const a5Landscape = PaperDetectionConfig(
    expectedAspectRatio: 148 / 210, // ~0.705
    paperWidthMm: 210,
    paperHeightMm: 148,
  );

  // ============================================================================
  // US paper presets
  // ============================================================================

  /// US Letter paper portrait (8.5 × 11 in = 215.9 × 279.4 mm)
  static const usLetterPortrait = PaperDetectionConfig(
    expectedAspectRatio: 215.9 / 279.4, // ~0.773
    paperWidthMm: 215.9,
    paperHeightMm: 279.4,
  );

  /// US Legal paper portrait (8.5 × 14 in = 215.9 × 355.6 mm)
  static const usLegalPortrait = PaperDetectionConfig(
    expectedAspectRatio: 215.9 / 355.6, // ~0.607
    paperWidthMm: 215.9,
    paperHeightMm: 355.6,
  );

  // ============================================================================
  // Other common formats
  // ============================================================================

  /// Business card (90 × 50 mm, ISO/IEC 7810 ID-1)
  static const businessCard = PaperDetectionConfig(
    expectedAspectRatio: 50 / 90, // ~0.556
    aspectRatioTolerance: 0.2,
    paperWidthMm: 90,
    paperHeightMm: 50,
  );

  /// Credit card size (85.6 × 53.98 mm, ISO/IEC 7810 ID-1)
  static const creditCard = PaperDetectionConfig(
    expectedAspectRatio: 53.98 / 85.6, // ~0.630
    aspectRatioTolerance: 0.15,
    paperWidthMm: 85.6,
    paperHeightMm: 53.98,
  );

  /// Square (1:1 aspect ratio)
  static const square = PaperDetectionConfig(
    expectedAspectRatio: 1.0,
    aspectRatioTolerance: 0.15,
    paperWidthMm: 100,
    paperHeightMm: 100,
  );

  /// Any rectangle (no aspect ratio constraint)
  static const anyRectangle = PaperDetectionConfig(
    expectedAspectRatio: 0, // No constraint
    aspectRatioTolerance: 1.0,
  );

  // ============================================================================
  // Preset metadata for UI
  // ============================================================================

  /// All available presets with display names
  static const Map<String, PaperDetectionConfig> presets = {
    'A0': a0Portrait,
    'A1': a1Portrait,
    'A2': a2Portrait,
    'A3': a3Portrait,
    'A4': a4Portrait,
    'A5': a5Portrait,
    'A6': a6Portrait,
    'A3 (landscape)': a3Landscape,
    'A4 (landscape)': a4Landscape,
    'A5 (landscape)': a5Landscape,
    'US Letter': usLetterPortrait,
    'US Legal': usLegalPortrait,
    'Business Card': businessCard,
    'Credit Card': creditCard,
    'Square': square,
    'Any Rectangle': anyRectangle,
  };

  /// Create config with camera intrinsics for pose estimation
  PaperDetectionConfig withCameraIntrinsics({required double focalLength, double? cx, double? cy}) {
    return PaperDetectionConfig(
      cannyThreshold1: cannyThreshold1,
      cannyThreshold2: cannyThreshold2,
      blurKernelSize: blurKernelSize,
      minAreaRatio: minAreaRatio,
      maxAreaRatio: maxAreaRatio,
      expectedAspectRatio: expectedAspectRatio,
      aspectRatioTolerance: aspectRatioTolerance,
      paperWidthMm: paperWidthMm,
      paperHeightMm: paperHeightMm,
      focalLength: focalLength,
      cx: cx ?? this.cx,
      cy: cy ?? this.cy,
    );
  }

  /// Copy with modified parameters
  PaperDetectionConfig copyWith({
    int? cannyThreshold1,
    int? cannyThreshold2,
    int? blurKernelSize,
    double? minAreaRatio,
    double? maxAreaRatio,
    double? expectedAspectRatio,
    double? aspectRatioTolerance,
    double? paperWidthMm,
    double? paperHeightMm,
    double? focalLength,
    double? cx,
    double? cy,
  }) {
    return PaperDetectionConfig(
      cannyThreshold1: cannyThreshold1 ?? this.cannyThreshold1,
      cannyThreshold2: cannyThreshold2 ?? this.cannyThreshold2,
      blurKernelSize: blurKernelSize ?? this.blurKernelSize,
      minAreaRatio: minAreaRatio ?? this.minAreaRatio,
      maxAreaRatio: maxAreaRatio ?? this.maxAreaRatio,
      expectedAspectRatio: expectedAspectRatio ?? this.expectedAspectRatio,
      aspectRatioTolerance: aspectRatioTolerance ?? this.aspectRatioTolerance,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      paperHeightMm: paperHeightMm ?? this.paperHeightMm,
      focalLength: focalLength ?? this.focalLength,
      cx: cx ?? this.cx,
      cy: cy ?? this.cy,
    );
  }
}
