import 'package:flutter/material.dart';
import 'package:homography_opencv_plugin/homography_opencv_plugin.dart';

/// Screen demonstrating homography computation from matched points
class HomographyTestScreen extends StatefulWidget {
  const HomographyTestScreen({super.key});

  @override
  State<HomographyTestScreen> createState() => _HomographyTestScreenState();
}

class _HomographyTestScreenState extends State<HomographyTestScreen> {
  HomographyMatrixResult? _result;
  String _status = 'Ready';

  @override
  void initState() {
    super.initState();
    _checkLibrary();
  }

  void _checkLibrary() {
    final lib = HomographyLib.instance;
    setState(() {
      _status = lib.isAvailable
          ? 'Library available (version: ${lib.version})'
          : 'Library NOT available: ${lib.loadError}';
    });
  }

  void _testHomography() {
    // Example matched points (simulated)
    final matchedPoints = [
      const MatchedPoint(x0: 0, y0: 0, x1: 10, y1: 5),
      const MatchedPoint(x0: 100, y0: 0, x1: 110, y1: 8),
      const MatchedPoint(x0: 100, y0: 100, x1: 115, y1: 105),
      const MatchedPoint(x0: 0, y0: 100, x1: 12, y1: 102),
      const MatchedPoint(x0: 50, y0: 50, x1: 62, y1: 55),
    ];

    final result = calculateHomographyFromMatchedPoints(matchedPoints, const Size(100, 100));

    setState(() {
      _result = result;
      _status = result != null ? 'Homography computed successfully!' : 'Failed to compute homography';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Homography Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(_status),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _testHomography,
                icon: const Icon(Icons.calculate),
                label: const Text('Test Homography'),
              ),
            ),
            const SizedBox(height: 16),
            if (_result != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Results', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      _buildResultRow('Inliers', '${_result!.numInliers}'),
                      _buildResultRow('Rotation', '${(_result!.rotation * 180 / 3.14159).toStringAsFixed(2)}°'),
                      _buildResultRow('Scale', _result!.scale.toStringAsFixed(3)),
                      _buildResultRow('Center', '${_result!.center}'),
                      const Divider(),
                      Text('Corners:', style: Theme.of(context).textTheme.titleSmall),
                      for (int i = 0; i < _result!.corners.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 4),
                          child: Text('Corner $i: ${_result!.corners[i]}'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
