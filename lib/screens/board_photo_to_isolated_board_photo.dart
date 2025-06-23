import 'dart:typed_data';

import 'package:chess_position_ocr/core/isolated_board_from_image.dart';
import 'package:chess_position_ocr/core/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:image_picker/image_picker.dart';

@pragma('vm:entry-point')
Future<(Uint8List?, String?)> heavyIsolationComputation(
  Uint8List imageData,
) async {
  return await isolateBoardPhoto(imageData);
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
  Future<(Uint8List?, String?)>? _fenFuture;

  Future<void> _takePhotoAndConvert() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    final imageData = await image.readAsBytes();
    final Future<(Uint8List?, String?)> fenFuture = flutterCompute(
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
        FutureBuilder<(Uint8List?, String?)>(
          future: _fenFuture,
          builder: (context, snapshot) {
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
            } else if (snapshot.hasData && _image != null) {
              final (newImageData, error) = snapshot.data!;
              if (error != null) {
                logger.e(error);
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  takePhotoButton,
                  Image.memory(_image!, width: 200, fit: BoxFit.cover),
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
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                ],
              );
            } else {
              return Column(
                children: [takePhotoButton, const Text("No FEN generated.")],
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
