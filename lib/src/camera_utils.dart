import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui show Image;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'paper_detection_result.dart';
import 'paper_detector.dart';

/// Утилиты для обработки кадров камеры
class CameraUtils {
  /// Извлекает grayscale данные из CameraImage (YUV420 формат)
  ///
  /// Возвращает Uint8List с grayscale данными и размеры изображения
  static ({Uint8List grayscaleBytes, int width, int height}) extractGrayscaleFromCameraImage(CameraImage image) {
    // Получаем Y-плоскость (grayscale) из YUV420
    final plane = image.planes[0];
    final int width = image.width;
    final int height = image.height;
    final int bytesPerRow = plane.bytesPerRow;

    // Если bytesPerRow != width, нужно копировать построчно
    Uint8List grayscaleBytes;
    if (bytesPerRow == width) {
      grayscaleBytes = plane.bytes;
    } else {
      // Удаляем padding из каждой строки
      grayscaleBytes = Uint8List(width * height);
      for (int y = 0; y < height; y++) {
        final srcOffset = y * bytesPerRow;
        final dstOffset = y * width;
        grayscaleBytes.setRange(dstOffset, dstOffset + width, plane.bytes, srcOffset);
      }
    }

    return (grayscaleBytes: grayscaleBytes, width: width, height: height);
  }

  /// Поворачивает результат детекции на -90 градусов (против часовой стрелки)
  ///
  /// Используется для Android, где камера возвращает повернутые изображения
  static PaperDetectionResult rotateResult90CCW(PaperDetectionResult result, int imageWidth, int imageHeight) {
    if (!result.isValid) return result;

    // Поворачиваем углы: (x, y) -> (height - y, x)
    final rotatedCorners = result.corners.map((corner) {
      return Offset(imageHeight - corner.dy, corner.dx);
    }).toList();

    // Поворачиваем центр
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

  /// Обрабатывает кадр камеры и возвращает результат детекции бумаги
  ///
  /// [image] - Кадр камеры в формате CameraImage
  /// [config] - Конфигурация детекции (опционально)
  /// [adjustConfigForCamera] - Настроить конфигурацию для камеры (баланс между чувствительностью и шумом)
  ///
  /// Возвращает результат детекции с учетом поворота для Android
  static PaperDetectionResult processCameraFrame(
    CameraImage image, {
    PaperDetectionConfig? config,
    bool adjustConfigForCamera = true,
  }) {
    // Извлекаем grayscale данные
    final extracted = extractGrayscaleFromCameraImage(image);

    // Настраиваем конфигурацию для камеры (баланс между чувствительностью и отсеиванием шума)
    final detectionConfig = adjustConfigForCamera && config != null
        ? config.copyWith(
            minAreaRatio: 0.1, // Бумага должна занимать минимум 10% кадра
            maxAreaRatio: 0.9,
            cannyThreshold1: 50,
            cannyThreshold2: 150,
            blurKernelSize: 7, // Больше размытие для уменьшения шума
          )
        : config;

    // Детектируем бумагу
    var result = detectPaper(
      imageData: extracted.grayscaleBytes,
      width: extracted.width,
      height: extracted.height,
      channels: 1, // Grayscale
      config: detectionConfig,
    );

    // Поворачиваем результат для Android (камера возвращает повернутые изображения)
    if (Platform.isAndroid && result.isValid) {
      result = rotateResult90CCW(result, extracted.width, extracted.height);
    }

    return result;
  }

  /// Загружает ui.Image из ImageProvider
  ///
  /// [imageProvider] - Провайдер изображения (NetworkImage, FileImage, AssetImage и т.д.)
  /// [imageConfiguration] - Конфигурация изображения (опционально)
  ///
  /// Возвращает Future с загруженным ui.Image
  /// Выбрасывает исключение, если загрузка не удалась
  static Future<ui.Image> loadImageFromProvider(
    ImageProvider imageProvider, {
    ImageConfiguration? imageConfiguration,
  }) async {
    final completer = Completer<ui.Image>();
    final imageStream = imageProvider.resolve(imageConfiguration ?? const ImageConfiguration());

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
    return completer.future;
  }
}
