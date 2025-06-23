import 'dart:typed_data';

import 'package:chess_position_ocr/core/isolated_board_from_image.dart';
import 'package:chess_position_ocr/core/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:image_picker/image_picker.dart';

@pragma('vm:entry-point')
Future<Map<String, dynamic>> heavyIsolationComputation(
  Uint8List imageData,
) async {
  final (result, error) = await isolateBoardPhoto(imageData);
  return {'result': result, 'error': error};
}

class BoardPhotoToIsolatedBoardPhoto extends StatefulWidget {
  const BoardPhotoToIsolatedBoardPhoto({super.key});

  @override
  State<BoardPhotoToIsolatedBoardPhoto> createState() =>
      _BoardPhotoToIsolatedBoardPhotoState();
}

class _BoardPhotoToIsolatedBoardPhotoState
    extends State<BoardPhotoToIsolatedBoardPhoto> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _image;
  Future<Map<String, dynamic>>? _fenFuture;

  Future<void> _takePhotoAndConvert() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    final imageData = await image.readAsBytes();
    final Future<Map<String, dynamic>> fenFuture = flutterCompute(
      heavyIsolationComputation,
      imageData,
    );

    setState(() {
      _image = imageData;
      _fenFuture = fenFuture;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    final takePhotoButton = TextButton(
      onPressed: _takePhotoAndConvert,
      child: const Text("Take photo"),
    );

    final List<Widget> content = [
      if (_fenFuture == null)
        takePhotoButton
      else if (_fenFuture != null)
        FutureBuilder<Map<String, dynamic>>(
          future: _fenFuture,
          builder: (context, snapshot) {
            final data = snapshot.data;
            final newImageData = data?['result'] as Uint8List?;
            final error = data?['error'] as String?;
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              );
            } else if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    takePhotoButton,
                    Text(
                      'Error: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            } else if (snapshot.hasData) {
              if (error != null) {
                logger.e(error);
              }

              final finalContens = [
                takePhotoButton,
                if (_image != null)
                  Image.memory(_image!, width: 150, fit: BoxFit.cover),
                const SizedBox(height: 16),
                if (error != null)
                  Text(
                    error,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                if (newImageData != null)
                  Image.memory(
                    newImageData,
                    width: 150,
                    height: 150,
                    fit: BoxFit.cover,
                  ),
              ];
              return MediaQuery.of(context).orientation == Orientation.portrait
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 20,
                      children: finalContens,
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 20,
                      children: finalContens,
                    );
            } else {
              return Column(
                children: [takePhotoButton, const Text("No image generated.")],
              );
            }
          },
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Chessboard isolation'),
      ),
      body: Center(
        child: isPortrait
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: content,
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: content,
              ),
      ),
    );
  }
}
