import 'dart:typed_data';

import 'package:chess_position_ocr/core/isolated_board_from_image.dart';
import 'package:chess_position_ocr/core/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:saver_gallery/saver_gallery.dart';

@pragma('vm:entry-point')
Future<Map<String, dynamic>> heavyIsolationComputation(
  Uint8List imageData,
) async {
  return await extractChessboard(imageData);
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
    final content = _fenFuture == null
        ? Container()
        : FutureBuilder<Map<String, dynamic>>(
            future: _fenFuture,
            builder: (context, snapshot) {
              final data = snapshot.data;
              final srcBytes = data?['src'] as Uint8List?;
              final dstBytes = data?['dst'] as Uint8List?;
              final error = data?['error'] as String?;

              if (snapshot.connectionState == ConnectionState.waiting) {
                return CircularProgressIndicator();
              } else if (snapshot.hasError) {
                return Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                );
              } else if (snapshot.hasData) {
                if (error != null) {
                  logger.e(error);
                }

                final sourceImage = srcBytes ?? (_image);
                if (srcBytes != null) {
                  saveToGallery(
                    srcBytes,
                    "testInput",
                    "png",
                  ).then((success) => {});
                }
                if (dstBytes != null) {
                  saveToGallery(
                    dstBytes,
                    "testOutput",
                    "png",
                  ).then((success) => {});
                }

                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 20,
                    children: [
                      if (sourceImage != null)
                        Image.memory(
                          sourceImage,
                          width: 300,
                          fit: BoxFit.cover,
                        ),
                      if (error != null)
                        Text(
                          error,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      if (dstBytes != null)
                        Image.memory(dstBytes, fit: BoxFit.cover),
                    ],
                  ),
                );
              } else {
                return const Text("No image generated.");
              }
            },
          );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Chessboard isolation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera),
            onPressed: _takePhotoAndConvert,
          ),
        ],
      ),
      body: Center(child: content),
    );
  }
}

// Save image from Uint8List to gallery
Future<bool> saveToGallery(
  Uint8List imageBytes,
  String fileName,
  String extension,
) async {
  // Save the image to the gallery (Pictures directory)
  final result = await SaverGallery.saveImage(
    imageBytes,
    quality: 100,
    extension: extension,
    fileName: fileName,
    skipIfExists: false,
  );

  return result.isSuccess;
}
