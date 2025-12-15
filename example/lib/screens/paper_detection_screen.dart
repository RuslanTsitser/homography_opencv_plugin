import 'dart:io';
import 'dart:math' show pi;
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

  // Corner smoothing - должен быть полем, а не геттером, чтобы сохранять состояние!
  final CornerSmoother _cornerSmoother = CornerSmoother(
    threshold: 10.0, // Игнорировать изменения меньше 10 пикселей
    smoothingFactor: 0.7, // Больше веса старым значениям для плавности
  );

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
      final image = await CameraUtils.loadImageFromProvider(imageProvider);
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
      final rawResult = CameraUtils.processCameraFrame(image, config: _defaultConfig, adjustConfigForCamera: true);

      // Применяем сглаживание координат
      final smoothedResult = _cornerSmoother.smooth(rawResult);

      if (mounted) {
        setState(() {
          _detectionResult = smoothedResult;
          if (smoothedResult.isValid) {
            _statusMessage = 'Paper detected! Area: ${smoothedResult.area.toInt()} px²';
            _lastDetectionResult = smoothedResult;
          } else {
            final extracted = CameraUtils.extractGrayscaleFromCameraImage(image);
            _statusMessage = 'No paper detected (${extracted.width}x${extracted.height})';
            // Сбрасываем сглаживание при потере детекции
            _cornerSmoother.reset();
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
      painter: ImageOverlayPainter(image: _overlayImage!, corners: result.corners, cameraSize: cameraSize),
    );
  }
}

/// Custom painter for drawing image overlay with perspective transformation
class ImageOverlayPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> corners;
  final Size cameraSize;
  final bool withBorder;

  const ImageOverlayPainter({
    required this.image,
    required this.corners,
    required this.cameraSize,
    this.withBorder = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    // Вычисляем масштаб для преобразования координат камеры в координаты экрана
    final scaleX = size.width / cameraSize.width;
    final scaleY = size.height / cameraSize.height;

    // Преобразуем углы в координаты экрана
    final screenCorners = corners.map((corner) {
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

    if (withBorder) {
      // Рисуем рамку
      final paint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawPath(clipPath, paint);
    }
    // Вычисляем матрицу перспективной трансформации
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final matrix = CameraUtils.computePerspectiveMatrix(
      imageSize: imageSize,
      canvasSize: size,
      corners: corners,
      cameraSize: cameraSize,
    );

    // Применяем трансформацию
    canvas.save();
    canvas.transform(matrix.storage);

    // Поворачиваем изображение на 90° для Android на канвасе
    if (Platform.isAndroid) {
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      // Переносим в центр изображения
      canvas.translate(imageSize.width / 2, imageSize.height / 2);
      // Поворачиваем на 90° по часовой стрелке
      canvas.rotate(-pi / 2); // π/2 радиан = 90°
      // Возвращаем обратно (с учетом того, что после поворота width и height меняются местами)
      canvas.translate(-imageSize.height / 2, -imageSize.width / 2);
      // Рисуем изображение
      canvas.drawImage(image, Offset.zero, Paint());
    } else {
      // Рисуем изображение без поворота для других платформ
      canvas.drawImage(image, Offset.zero, Paint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ImageOverlayPainter oldDelegate) {
    return corners != oldDelegate.corners || image != oldDelegate.image;
  }
}
