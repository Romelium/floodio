import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class LocalImageDisplay extends StatefulWidget {
  final String imageId;
  const LocalImageDisplay({super.key, required this.imageId});

  @override
  State<LocalImageDisplay> createState() => _LocalImageDisplayState();
}

class _LocalImageDisplayState extends State<LocalImageDisplay> {
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${widget.imageId}');
    if (await file.exists()) {
      if (mounted) {
        setState(() {
          _imageFile = file;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_imageFile == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.black,
                  iconTheme: const IconThemeData(color: Colors.white),
                ),
                body: Center(
                  child: InteractiveViewer(child: Image.file(_imageFile!)),
                ),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            _imageFile!,
            height: 150,
            width: double.infinity,
            fit: BoxFit.cover,
            cacheWidth: 800,
          ),
        ),
      ),
    );
  }
}
