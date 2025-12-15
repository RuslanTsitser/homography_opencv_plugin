# homography_opencv_plugin

Flutter plugin for computing homography from matched points using OpenCV with RANSAC.

## Features

- Compute perspective transformation (homography) from matched point pairs
- RANSAC for robust estimation with outlier rejection
- Pre-built native libraries with OpenCV statically linked
- Fallback to simple similarity transform if native library unavailable
- Supports iOS and Android

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  homography_opencv_plugin:
    git:
      url: https://github.com/your-repo/homography_lib.git
      path: homography_opencv_plugin
```

Or use path dependency:

```yaml
dependencies:
  homography_opencv_plugin:
    path: ../path/to/homography_opencv_plugin
```

## Usage

```dart
import 'package:homography_opencv_plugin/homography_opencv_plugin.dart';

// Create matched point pairs (from LightGlue, ORB, or any other matcher)
final matchedPoints = [
  MatchedPoint(x0: 0, y0: 0, x1: 10, y1: 5),
  MatchedPoint(x0: 100, y0: 0, x1: 110, y1: 8),
  MatchedPoint(x0: 100, y0: 100, x1: 115, y1: 105),
  MatchedPoint(x0: 0, y0: 100, x1: 12, y1: 102),
  // ... more points for better accuracy
];

// Compute homography
final result = calculateHomographyFromMatchedPoints(
  matchedPoints,
  Size(100, 100), // anchor image size
);

if (result != null) {
  print('Inliers: ${result.numInliers}');
  print('Rotation: ${result.rotation} rad');
  print('Scale: ${result.scale}');
  print('Center: ${result.center}');
  print('Corners: ${result.corners}');
  
  // Use Matrix4 with Flutter Transform widget
  Transform(
    transform: result.matrix,
    child: YourWidget(),
  );
}
```

## API

### `calculateHomographyFromMatchedPoints`

```dart
HomographyMatrixResult? calculateHomographyFromMatchedPoints(
  List<MatchedPoint> matchedPoints,
  Size anchorSize,
)
```

Computes homography matrix from matched points using OpenCV with RANSAC.

**Parameters:**
- `matchedPoints` - List of matched point pairs (minimum 4 required)
- `anchorSize` - Size of the anchor/reference image in pixels

**Returns:**
- `HomographyMatrixResult` on success, `null` if homography cannot be computed

### `HomographyMatrixResult`

```dart
class HomographyMatrixResult {
  final Matrix4 matrix;        // 4x4 transformation matrix for Flutter
  final List<Offset> corners;  // Four corners of detected anchor
  final Offset center;         // Center point
  final double rotation;       // Rotation angle in radians
  final double scale;          // Scale factor
  final int numInliers;        // Number of RANSAC inliers
}
```

### `MatchedPoint`

```dart
class MatchedPoint {
  final double x0, y0;  // Point on anchor image
  final double x1, y1;  // Corresponding point on scene/camera image
}
```

### `HomographyLib`

Low-level singleton for direct FFI access:

```dart
final lib = HomographyLib.instance;

// Check if native library is available
if (lib.isAvailable) {
  print('Library version: ${lib.version}');
}
```

## Platform Support

| Platform | Support |
|----------|---------|
| Android  | ✅ arm64-v8a, armeabi-v7a |
| iOS      | ✅ arm64 (device), arm64+x86_64 (simulator) |
| macOS    | ❌ |
| Windows  | ❌ |
| Linux    | ❌ |
| Web      | ❌ |

## Requirements

- Flutter >= 3.3.0
- iOS >= 13.0
- Android minSdk >= 24

## License

MIT License
