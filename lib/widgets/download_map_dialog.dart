import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/map_downloader_provider.dart';

class DownloadMapDialog extends ConsumerStatefulWidget {
  final LatLngBounds bounds;
  final int currentZoom;

  const DownloadMapDialog({
    super.key,
    required this.bounds,
    required this.currentZoom,
  });

  @override
  ConsumerState<DownloadMapDialog> createState() => _DownloadMapDialogState();
}

class _DownloadMapDialogState extends ConsumerState<DownloadMapDialog> {
  late int _maxZoom;

  @override
  void initState() {
    super.initState();
    _maxZoom = max(widget.currentZoom, min(widget.currentZoom + 2, 18));
  }

  @override
  Widget build(BuildContext context) {
    final downloader = ref.read(mapDownloaderProvider.notifier);
    final tileCount = downloader.estimateTileCount(
      widget.bounds,
      widget.currentZoom,
      _maxZoom,
    );
    final estimatedSizeMB =
        (tileCount * 0.015); // rough estimate: 15KB per tile

    return AlertDialog(
      title: const Text('Download Offline Map'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Download the currently visible area for offline use.'),
          const SizedBox(height: 16),
          Text('Current Zoom: ${widget.currentZoom}'),
          Row(
            children: [
              const Text('Max Zoom: '),
              Expanded(
                child: widget.currentZoom >= 18
                    ? const SizedBox.shrink()
                    : Slider(
                        value: _maxZoom.toDouble(),
                        min: widget.currentZoom.toDouble(),
                        max: max(18.0, widget.currentZoom.toDouble()),
                        divisions: max(1, 18 - widget.currentZoom),
                        label: _maxZoom.toString(),
                        onChanged: (val) {
                          setState(() {
                            _maxZoom = val.toInt();
                          });
                        },
                      ),
              ),
              Text(_maxZoom.toString()),
            ],
          ),
          const SizedBox(height: 8),
          Text('Estimated Tiles: $tileCount'),
          Text('Estimated Size: ~${estimatedSizeMB.toStringAsFixed(1)} MB'),
          if (tileCount > 10000)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                'Warning: Large download. This may take a long time and consume significant storage.',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: tileCount > 50000
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(context);
                  downloader.downloadRegion(
                    widget.bounds,
                    widget.currentZoom,
                    _maxZoom,
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  );
                },
          child: const Text('Download'),
        ),
      ],
    );
  }
}
