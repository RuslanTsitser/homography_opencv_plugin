import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:homography_opencv_plugin/homography_opencv_plugin.dart';
import 'package:permission_handler/permission_handler.dart';

const _image =
    'https://parsefiles.back4app.com/gy5DcBsmJFEhxkEKeKlArNJaLJ39WGVyZXHSKXPD/892bc31ef87064339f9a04bdb45db5c7_L11-12.png';

/// Screen demonstrating paper detection using camera
class PaperDetectionScreen extends StatefulWidget {
  const PaperDetectionScreen({super.key});

  @override
  State<PaperDetectionScreen> createState() => _PaperDetectionScreenState();
}

class _PaperDetectionScreenState extends State<PaperDetectionScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String _statusMessage = 'Initializing...';
  PaperDetectionResult? _detectionResult;
  PaperDetectionResult? _lastDetectionResult;

  // Selected paper preset
  String _selectedPresetName = 'A4';
  PaperDetectionConfig _selectedConfig = PaperDetectionConfig.a4Portrait;

  // Processing settings
  bool _showDebugInfo = true;
  final int _frameSkip = 2; // Process every Nth frame
  int _frameCount = 0;

  // Loaded image for overlay
  ui.Image? _overlayImage;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadOverlayImage();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _overlayImage?.dispose();
    super.dispose();
  }

  Future<void> _loadOverlayImage() async {
    try {
      final imageProvider = NetworkImage(_image);
      final completer = Completer<ui.Image>();
      final imageStream = imageProvider.resolve(const ImageConfiguration());

      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (!completer.isCompleted) {
            completer.complete(info.image);
          }
          imageStream.removeListener(listener);
        },
        onError: (exception, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(exception, stackTrace);
          }
          imageStream.removeListener(listener);
        },
      );

      imageStream.addListener(listener);

      final image = await completer.future;
      if (mounted) {
        setState(() {
          _overlayImage = image;
        });
      }
    } catch (e) {
      debugPrint('Failed to load overlay image: $e');
    }
  }

  Future<void> _initializeCamera() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() => _statusMessage = 'Camera permission denied');
      return;
    }

    // Get available cameras
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() => _statusMessage = 'No cameras available');
        return;
      }

      // Initialize camera controller
      _cameraController = CameraController(
        _cameras!.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      // Start image stream
      await _cameraController!.startImageStream(_onCameraFrame);

      setState(() {
        _isInitialized = true;
        _statusMessage = 'Ready - Point camera at paper';
      });
    } catch (e) {
      setState(() => _statusMessage = 'Camera error: $e');
    }
  }

  void _onCameraFrame(CameraImage image) {
    // Skip frames to reduce CPU load
    _frameCount++;
    if (_frameCount % _frameSkip != 0) return;

    // Prevent concurrent processing
    if (_isProcessing) return;
    _isProcessing = true;

    // Process frame
    _processFrame(image).then((_) {
      _isProcessing = false;
    });
  }

  /// Rotate coordinates -90 degrees (clockwise) for Android
  PaperDetectionResult _rotateResult90CCW(PaperDetectionResult result, int imageWidth, int imageHeight) {
    if (!result.isValid) return result;

    // Rotate corners: (x, y) -> (height - y, x)
    final rotatedCorners = result.corners.map((corner) {
      return Offset(imageHeight - corner.dy, corner.dx);
    }).toList();

    // Rotate center
    final rotatedCenter = Offset(imageHeight - result.center.dy, result.center.dx);

    return PaperDetectionResult(
      corners: rotatedCorners,
      center: rotatedCenter,
      homography: result.homography,
      rotationVector: result.rotationVector,
      translationVector: result.translationVector,
      area: result.area,
      perimeter: result.perimeter,
      aspectRatio: result.aspectRatio,
      isValid: result.isValid,
    );
  }

  Future<void> _processFrame(CameraImage image) async {
    try {
      // Get Y plane (grayscale) from YUV420
      final plane = image.planes[0];
      final int width = image.width;
      final int height = image.height;
      final int bytesPerRow = plane.bytesPerRow;

      // If bytesPerRow != width, we need to copy row by row
      Uint8List grayscaleBytes;
      if (bytesPerRow == width) {
        grayscaleBytes = plane.bytes;
      } else {
        // Remove padding from each row
        grayscaleBytes = Uint8List(width * height);
        for (int y = 0; y < height; y++) {
          final srcOffset = y * bytesPerRow;
          final dstOffset = y * width;
          grayscaleBytes.setRange(dstOffset, dstOffset + width, plane.bytes, srcOffset);
        }
      }

      // Adjust config: balance between sensitivity and noise rejection
      final config = _selectedConfig.copyWith(
        minAreaRatio: 0.1, // Paper should be at least 10% of frame
        maxAreaRatio: 0.9,
        cannyThreshold1: 50,
        cannyThreshold2: 150,
        blurKernelSize: 7, // More blur to reduce noise
      );

      // Detect paper
      var result = detectPaper(
        imageData: grayscaleBytes,
        width: width,
        height: height,
        channels: 1, // Grayscale
        config: config,
      );

      // Rotate result for Android (camera returns rotated images)
      if (Platform.isAndroid && result.isValid) {
        result = _rotateResult90CCW(result, width, height);
      }

      if (mounted) {
        setState(() {
          _detectionResult = result;
          if (result.isValid) {
            _statusMessage = 'Paper detected! Area: ${result.area.toInt()} px²';
            _lastDetectionResult = result;
          } else {
            _statusMessage = 'No paper detected (${width}x$height)';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Error: $e');
      }
    }
  }

  void _onPresetChanged(String? presetName) {
    if (presetName == null) return;
    final config = PaperDetectionConfig.presets[presetName];
    if (config == null) return;

    setState(() {
      _selectedPresetName = presetName;
      _selectedConfig = config;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paper Detection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: Icon(_showDebugInfo ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showDebugInfo = !_showDebugInfo),
            tooltip: 'Toggle debug info',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                const Icon(Icons.description, size: 20),
                const SizedBox(width: 8),
                const Text('Paper format:'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedPresetName,
                    isExpanded: true,
                    onChanged: _onPresetChanged,
                    items: PaperDetectionConfig.presets.keys
                        .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: _detectionResult?.isValid == true
            ? Colors.green.shade100
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Row(
          children: [
            Icon(
              _detectionResult?.isValid == true ? Icons.check_circle : Icons.search,
              color: _detectionResult?.isValid == true ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(_statusMessage)),
          ],
        ),
      ),
      body: _isInitialized
          ? AspectRatio(
              aspectRatio: 1 / _cameraController!.value.previewSize!.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Camera preview
                  CameraPreview(_cameraController!),

                  // Detection overlay with image
                  if (_lastDetectionResult != null && _lastDetectionResult!.isValid)
                    _buildImageOverlay(_lastDetectionResult!),

                  // Debug info overlay
                  if (_showDebugInfo) Positioned(left: 8, top: 8, child: _buildDebugOverlay()),
                ],
              ),
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [const CircularProgressIndicator(), const SizedBox(height: 16), Text(_statusMessage)],
              ),
            ),
    );
  }

  Widget _buildImageOverlay(PaperDetectionResult result) {
    if (_overlayImage == null) return const SizedBox.shrink();

    final cameraSize = Size(_cameraController!.value.previewSize!.height, _cameraController!.value.previewSize!.width);

    return CustomPaint(
      painter: _ImageOverlayPainter(image: _overlayImage!, result: result, cameraSize: cameraSize),
    );
  }

  Widget _buildDebugOverlay() {
    final result = _detectionResult;
    final camSize = _cameraController?.value.previewSize;
    final isDetectorAvailable = PaperDetector.instance.isAvailable;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Detector: ${isDetectorAvailable ? "OK" : "NOT AVAILABLE"}',
            style: TextStyle(color: isDetectorAvailable ? Colors.greenAccent : Colors.redAccent, fontSize: 11),
          ),
          if (camSize != null)
            Text(
              'Camera: ${camSize.width.toInt()}x${camSize.height.toInt()}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          Text('Preset: $_selectedPresetName', style: const TextStyle(color: Colors.white, fontSize: 12)),
          Text(
            'Expected AR: ${_selectedConfig.expectedAspectRatio.toStringAsFixed(3)}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          if (result != null && result.isValid) ...[
            const SizedBox(height: 4),
            Text(
              'Detected AR: ${result.aspectRatio.toStringAsFixed(3)}',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
            ),
            Text('Area: ${result.area.toInt()} px²', style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
            Text(
              'Size: ${result.width.toInt()} × ${result.height.toInt()}',
              style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/// Custom painter for drawing image overlay with perspective transformation
class _ImageOverlayPainter extends CustomPainter {
  final ui.Image image;
  final PaperDetectionResult result;
  final Size cameraSize;

  _ImageOverlayPainter({required this.image, required this.result, required this.cameraSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (!result.isValid || result.corners.length != 4) return;

    // Вычисляем масштаб для преобразования координат камеры в координаты экрана
    final scaleX = size.width / cameraSize.width;
    final scaleY = size.height / cameraSize.height;

    // Преобразуем углы в координаты экрана
    final screenCorners = result.corners.map((corner) {
      return Offset(corner.dx * scaleX, corner.dy * scaleY);
    }).toList();

    // Создаем путь для обрезки
    final clipPath = Path()
      ..moveTo(screenCorners[0].dx, screenCorners[0].dy)
      ..lineTo(screenCorners[1].dx, screenCorners[1].dy)
      ..lineTo(screenCorners[2].dx, screenCorners[2].dy)
      ..lineTo(screenCorners[3].dx, screenCorners[3].dy)
      ..close();

    // Применяем обрезку
    canvas.clipPath(clipPath);

    // Вычисляем матрицу трансформации для перспективы
    final srcPoints = [
      Offset(0, 0), // top-left
      Offset(image.width.toDouble(), 0), // top-right
      Offset(image.width.toDouble(), image.height.toDouble()), // bottom-right
      Offset(0, image.height.toDouble()), // bottom-left
    ];

    // Вычисляем матрицу перспективной трансформации
    final matrix = _computePerspectiveMatrix(srcPoints, screenCorners);

    // Применяем трансформацию
    canvas.save();
    canvas.transform(matrix.storage);

    // Рисуем изображение
    canvas.drawImage(image, Offset.zero, Paint());
    canvas.restore();
  }

  Matrix4 _computePerspectiveMatrix(List<Offset> src, List<Offset> dst) {
    // Вычисляем матрицу перспективной трансформации через решение системы уравнений
    // Используем упрощенный подход через аффинную трансформацию
    // Для полной перспективы нужна более сложная математика

    // Вычисляем центр исходного изображения
    final srcCenter = Offset(
      src.map((p) => p.dx).reduce((a, b) => a + b) / src.length,
      src.map((p) => p.dy).reduce((a, b) => a + b) / src.length,
    );

    // Вычисляем центр целевого многоугольника
    final dstCenter = Offset(
      dst.map((p) => p.dx).reduce((a, b) => a + b) / dst.length,
      dst.map((p) => p.dy).reduce((a, b) => a + b) / dst.length,
    );

    // Вычисляем масштаб
    final srcWidth = (src[1] - src[0]).distance;
    final srcHeight = (src[3] - src[0]).distance;
    final dstWidth = (dst[1] - dst[0]).distance;
    final dstHeight = (dst[3] - dst[0]).distance;

    final scaleX = dstWidth / srcWidth;
    final scaleY = dstHeight / srcHeight;

    // Вычисляем угол поворота (упрощенно)
    final srcVec = src[1] - src[0];
    final dstVec = dst[1] - dst[0];
    final angle = (dstVec.direction - srcVec.direction);

    // Создаем матрицу трансформации
    final matrix = Matrix4.identity()
      ..translate(dstCenter.dx, dstCenter.dy)
      ..rotateZ(angle)
      ..scale(scaleX, scaleY)
      ..translate(-srcCenter.dx, -srcCenter.dy);

    return matrix;
  }

  @override
  bool shouldRepaint(covariant _ImageOverlayPainter oldDelegate) {
    return result != oldDelegate.result || image != oldDelegate.image;
  }
}

/// Custom painter for drawing paper detection overlay
class PaperOverlayPainter extends CustomPainter {
  final PaperDetectionResult result;
  final Size cameraSize;

  PaperOverlayPainter({required this.result, required this.cameraSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (!result.isValid || result.corners.length != 4) return;

    // Calculate scale factors (camera coords -> screen coords)
    final scaleX = size.width / cameraSize.width;
    final scaleY = size.height / cameraSize.height;

    // Transform corners to screen coordinates
    final screenCorners = result.corners.map((corner) {
      return Offset(corner.dx * scaleX, corner.dy * scaleY);
    }).toList();

    // Draw filled polygon with semi-transparent color
    final fillPaint = Paint()
      ..color = Colors.green.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(screenCorners[0].dx, screenCorners[0].dy)
      ..lineTo(screenCorners[1].dx, screenCorners[1].dy)
      ..lineTo(screenCorners[2].dx, screenCorners[2].dy)
      ..lineTo(screenCorners[3].dx, screenCorners[3].dy)
      ..close();

    canvas.drawPath(path, fillPaint);

    // Draw border
    final borderPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawPath(path, borderPaint);

    // Draw corner points
    final cornerPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;

    for (int i = 0; i < screenCorners.length; i++) {
      canvas.drawCircle(screenCorners[i], 8, cornerPaint);

      // Draw corner index
      final textPainter = TextPainter(
        text: TextSpan(
          text: '$i',
          style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, screenCorners[i] - Offset(textPainter.width / 2, textPainter.height / 2));
    }

    // Draw center point
    final centerX = result.center.dx * scaleX;
    final centerY = result.center.dy * scaleY;
    canvas.drawCircle(Offset(centerX, centerY), 6, Paint()..color = Colors.red);
  }

  @override
  bool shouldRepaint(covariant PaperOverlayPainter oldDelegate) {
    return result != oldDelegate.result;
  }
}
