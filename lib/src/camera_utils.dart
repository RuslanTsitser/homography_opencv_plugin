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

  /// Вычисляет матрицу перспективной трансформации для преобразования изображения на холст
  ///
  /// [imageSize] - Размер исходного изображения
  /// [canvasSize] - Размер холста (экрана)
  /// [corners] - Углы детектированного объекта в координатах камеры
  /// [cameraSize] - Размер камеры для масштабирования координат
  ///
  /// Возвращает Matrix4 для применения перспективной трансформации
  /// Использует упрощенный подход через аффинную трансформацию
  static Matrix4 computePerspectiveMatrix(
    Size imageSize,
    Size canvasSize,
    List<Offset> corners,
    Size cameraSize,
  ) {
    if (corners.length != 4) {
      return Matrix4.identity();
    }

    // Вычисляем масштаб для преобразования координат камеры в координаты экрана
    final scaleX = canvasSize.width / cameraSize.width;
    final scaleY = canvasSize.height / cameraSize.height;

    // Преобразуем углы в координаты экрана
    final dstPoints = corners.map((corner) {
      return Offset(corner.dx * scaleX, corner.dy * scaleY);
    }).toList();

    // Исходные точки изображения (углы изображения)
    final srcPoints = [
      Offset(0, 0), // top-left
      Offset(imageSize.width, 0), // top-right
      Offset(imageSize.width, imageSize.height), // bottom-right
      Offset(0, imageSize.height), // bottom-left
    ];

    // Используем первые 3 точки для вычисления аффинной трансформации
    // Аффинная трансформация: x' = a*x + b*y + c, y' = d*x + e*y + f
    // Нужно решить систему из 6 уравнений для 6 неизвестных (a, b, c, d, e, f)

    // Используем первые 3 точки для решения системы
    final src0 = srcPoints[0];
    final src1 = srcPoints[1];
    final src2 = srcPoints[2];

    final dst0 = dstPoints[0];
    final dst1 = dstPoints[1];
    final dst2 = dstPoints[2];

    // Решаем систему уравнений для аффинной трансформации
    // Используем метод Крамера для решения 2x2 системы для каждой координаты

    // Для x-координаты: решаем систему
    // a*x0 + b*y0 + c = x0'
    // a*x1 + b*y1 + c = x1'
    // a*x2 + b*y2 + c = x2'

    // Упрощаем: используем только 2 точки и вычисляем параметры
    // Для упрощения используем подход с центром и масштабом

    // Вычисляем центр из всех точек изображения
    final srcCenter = Offset(imageSize.width / 2, imageSize.height / 2);

    // Вычисляем центр целевого многоугольника из всех точек
    final dstCenter = Offset(
      dstPoints.map((p) => p.dx).reduce((a, b) => a + b) / dstPoints.length,
      dstPoints.map((p) => p.dy).reduce((a, b) => a + b) / dstPoints.length,
    );

    // Вычисляем векторы от центра для определения масштаба и поворота
    final srcVec1 = src1 - src0;
    final srcVec2 = src2 - src0;
    final dstVec1 = dst1 - dst0;
    final dstVec2 = dst2 - dst0;

    // Вычисляем масштаб по первой стороне
    final srcLen1 = srcVec1.distance;
    final dstLen1 = dstVec1.distance;
    final scale1 = dstLen1 / srcLen1;

    // Вычисляем масштаб по второй стороне
    final srcLen2 = srcVec2.distance;
    final dstLen2 = dstVec2.distance;
    final scale2 = dstLen2 / srcLen2;

    // Используем средний масштаб
    final avgScale = (scale1 + scale2) / 2;

    // Вычисляем угол поворота по первой стороне
    final angle = dstVec1.direction - srcVec1.direction;

    // Создаем матрицу трансформации
    // Порядок: перенос в центр источника, поворот, масштаб, перенос в центр назначения
    final matrix = Matrix4.identity()
      ..translate(dstCenter.dx, dstCenter.dy, 0)
      ..scale(avgScale, avgScale, 1)
      ..rotateZ(angle)
      ..translate(-srcCenter.dx, -srcCenter.dy, 0);

    return matrix;
  }
}
