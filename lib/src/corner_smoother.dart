import 'dart:ui' show Offset;

import 'paper_detection_result.dart';

/// Класс для сглаживания координат углов детектированного объекта
///
/// Использует пороговую фильтрацию и экспоненциальное сглаживание
/// для уменьшения дрожания координат при небольших смещениях
class CornerSmoother {
  /// Порог изменения в пикселях (изменения меньше этого значения игнорируются)
  final double threshold;

  /// Коэффициент сглаживания (0.0 - только новые значения, 1.0 - только старые)
  /// Рекомендуемое значение: 0.3-0.7
  final double smoothingFactor;

  /// Последние сглаженные координаты углов
  List<Offset>? _lastSmoothedCorners;

  /// Последний валидный результат
  PaperDetectionResult? _lastResult;

  CornerSmoother({
    this.threshold = 5.0,
    this.smoothingFactor = 0.5,
  });

  /// Сглаживает координаты углов результата детекции
  ///
  /// [result] - Новый результат детекции
  ///
  /// Возвращает сглаженный результат или исходный, если сглаживание не применимо
  PaperDetectionResult smooth(PaperDetectionResult result) {
    // Если результат невалидный, сбрасываем состояние
    if (!result.isValid) {
      _lastSmoothedCorners = null;
      _lastResult = null;
      return result;
    }

    // Если это первый валидный результат, сохраняем его как есть
    if (_lastSmoothedCorners == null || _lastResult == null) {
      _lastSmoothedCorners = List<Offset>.from(result.corners);
      _lastResult = result;
      return result;
    }

    // Вычисляем среднее изменение всех углов
    final avgChange = _computeAverageChange(result.corners, _lastSmoothedCorners!);

    // Если среднее изменение меньше порога, возвращаем старый результат
    if (avgChange < threshold) {
      return _lastResult!;
    }

    // Применяем адаптивное экспоненциальное сглаживание
    // Чем больше изменение, тем больше вес новых значений
    final adaptiveSmoothingFactor = _computeAdaptiveSmoothingFactor(avgChange);
    final smoothedCorners = _applySmoothing(result.corners, _lastSmoothedCorners!, adaptiveSmoothingFactor);

    // Создаем новый результат со сглаженными координатами
    final smoothedResult = PaperDetectionResult(
      corners: smoothedCorners,
      center: _computeCenter(smoothedCorners),
      homography: result.homography,
      rotationVector: result.rotationVector,
      translationVector: result.translationVector,
      area: result.area,
      perimeter: result.perimeter,
      aspectRatio: result.aspectRatio,
      isValid: true,
    );

    // Сохраняем для следующей итерации
    _lastSmoothedCorners = smoothedCorners;
    _lastResult = smoothedResult;

    return smoothedResult;
  }

  /// Вычисляет среднее изменение всех углов
  double _computeAverageChange(List<Offset> newCorners, List<Offset> oldCorners) {
    if (newCorners.length != oldCorners.length || newCorners.isEmpty) {
      return double.infinity; // Требует обновления
    }

    double totalChange = 0.0;
    for (int i = 0; i < newCorners.length; i++) {
      totalChange += (newCorners[i] - oldCorners[i]).distance;
    }

    return totalChange / newCorners.length;
  }

  /// Вычисляет адаптивный коэффициент сглаживания на основе величины изменения
  ///
  /// При малых изменениях использует больше сглаживания (больше веса старым значениям)
  /// При больших изменениях использует меньше сглаживания (больше веса новым значениям)
  double _computeAdaptiveSmoothingFactor(double avgChange) {
    // Нормализуем изменение относительно порога
    final normalizedChange = avgChange / threshold;

    // При малых изменениях (1.0-1.5x порога) используем больше сглаживания
    // При больших изменениях (>1.5x порога) используем меньше сглаживания
    if (normalizedChange <= 1.5) {
      // Малые изменения: увеличиваем сглаживание до 0.9
      final ratio = normalizedChange / 1.5; // 0.0 - 1.0
      return smoothingFactor + (0.9 - smoothingFactor) * (1.0 - ratio);
    } else {
      // Большие изменения: уменьшаем сглаживание, но не меньше 0.3
      final excess = (normalizedChange - 1.5) / 3.5; // нормализуем до 0-1 для изменений 1.5-5.0x
      final factor = smoothingFactor * (1.0 - excess.clamp(0.0, 0.6));
      return factor.clamp(0.3, smoothingFactor);
    }
  }

  /// Применяет экспоненциальное сглаживание к координатам
  List<Offset> _applySmoothing(List<Offset> newCorners, List<Offset> oldCorners, [double? customSmoothingFactor]) {
    if (newCorners.length != oldCorners.length) {
      return List<Offset>.from(newCorners);
    }

    final factor = customSmoothingFactor ?? smoothingFactor;

    return List.generate(newCorners.length, (i) {
      final newCorner = newCorners[i];
      final oldCorner = oldCorners[i];

      // Экспоненциальное сглаживание: smoothed = alpha * new + (1 - alpha) * old
      // где alpha = 1 - smoothingFactor
      final alpha = 1.0 - factor;
      final smoothedX = alpha * newCorner.dx + factor * oldCorner.dx;
      final smoothedY = alpha * newCorner.dy + factor * oldCorner.dy;

      return Offset(smoothedX, smoothedY);
    });
  }

  /// Вычисляет центр из углов
  Offset _computeCenter(List<Offset> corners) {
    if (corners.isEmpty) return Offset.zero;

    double sumX = 0.0;
    double sumY = 0.0;
    for (final corner in corners) {
      sumX += corner.dx;
      sumY += corner.dy;
    }

    return Offset(sumX / corners.length, sumY / corners.length);
  }

  /// Сбрасывает состояние сглаживания
  void reset() {
    _lastSmoothedCorners = null;
    _lastResult = null;
  }
}
