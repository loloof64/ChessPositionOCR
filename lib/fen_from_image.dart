import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

Future<String> predictFEN(Uint8List imageBytes) async {
  // Load the TFLite model
  final interpreter = await Interpreter.fromAsset('assets/models/chess_piece_model.tflite');

  // Decode the image
  img.Image? image = img.decodeImage(imageBytes);
  if (image == null) {
    throw Exception('Failed to decode image');
  }

  // Resize image to the input size expected by the model
  final inputShape = interpreter.getInputTensor(0).shape;
  final height = inputShape[1];
  final width = inputShape[2];
  final resized = img.copyResize(image, width: width, height: height);

  // Prepare normalized input tensor [1, height, width, 3]
  final input = List.generate(1, (_) =>
    List.generate(height, (y) =>
      List.generate(width, (x) {
        final pixel = resized.getPixel(x, y);
        return [
          pixel.r / 255.0,
          pixel.g / 255.0,
          pixel.b / 255.0,
        ];
      })
    )
  );

  // Prepare output buffer (adjust shape based on your model's output)
  final outputShape = interpreter.getOutputTensor(0).shape;
  final output = List.generate(outputShape[0], (_) => List.filled(outputShape[1], 0));

  // Run inference
  interpreter.run(input, output);

  // Decode output as ASCII (filter nulls)
  final asciiCodes = output[0].where((code) => code != 0).cast<int>();
  final fen = String.fromCharCodes(asciiCodes);
  return fen;
}
