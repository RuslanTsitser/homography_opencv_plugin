import 'dart:async';
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

  // Processing settings
  final int _frameSkip = 2; // Process every Nth frame
  int _frameCount = 0;

  // Default config
  static const PaperDetectionConfig _defaultConfig = PaperDetectionConfig.anyRectangle;

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

  Future<void> _processFrame(CameraImage image) async {
    try {
      // Обрабатываем кадр камеры используя методы плагина
      final result = CameraUtils.processCameraFrame(image, config: _defaultConfig, adjustConfigForCamera: true);

      if (mounted) {
        setState(() {
          _detectionResult = result;
          if (result.isValid) {
            _statusMessage = 'Paper detected! Area: ${result.area.toInt()} px²';
            _lastDetectionResult = result;
          } else {
            final extracted = CameraUtils.extractGrayscaleFromCameraImage(image);
            _statusMessage = 'No paper detected (${extracted.width}x${extracted.height})';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paper Detection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
