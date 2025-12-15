/// Flutter plugin for computing homography from matched points using OpenCV.
///
/// This plugin provides homography computation with RANSAC for robust estimation.
/// It includes pre-built native libraries with OpenCV statically linked.
///
/// ## Features
///
/// ### Homography from Matched Points
/// Use [calculateHomographyFromMatchedPoints] to compute homography matrix
/// from point correspondences (e.g., from feature matching like LightGlue).
///
/// ### Paper/Document Detection (NEW)
/// Use [PaperDetector] or convenience functions [detectPaper]/[detectPaperEncoded]
/// to detect rectangular paper-like objects using contour-based detection.
/// This is useful for document scanning, AR applications, etc.
///
/// ```dart
/// // Detect paper in camera frame
/// final result = detectPaper(
///   imageData: rgbBytes,
///   width: 640,
///   height: 480,
///   channels: 3,
///   config: PaperDetectionConfig.a4Portrait,
/// );
///
/// if (result.isValid) {
///   // Use result.corners for drawing overlay
///   // Use result.homography for perspective correction
/// }
/// ```
library;

export 'src/camera_utils.dart';
export 'src/homography_lib.dart';
export 'src/homography_result.dart';
export 'src/paper_detection_result.dart';
export 'src/paper_detector.dart';
