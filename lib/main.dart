import 'package:chess_position_ocr/core/fen_from_image.dart';
import 'package:chess_position_ocr/widgets/chessboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

Future<String?> heavyFenComputation(Uint8List imageData) async {
  return await predictFen(imageData);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _image;
  Future<String?>? _fenFuture;

  Future<void> _takePhotoAndAnalyze() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    final imageData = await image.readAsBytes();
    final Future<String?> fenFuture = kDebugMode
        ? Future.value(await heavyFenComputation(imageData))
        : compute(heavyFenComputation, imageData);
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
      onPressed: _takePhotoAndAnalyze,
      child: const Text("Take photo"),
    );

    final List<Widget> content = [
      if (_fenFuture == null)
        takePhotoButton
      else if (_fenFuture != null)
        FutureBuilder<String?>(
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
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  takePhotoButton,
                  Image.memory(_image!, width: 200, fit: BoxFit.cover),
                  const SizedBox(height: 16),
                  Chessboard(fen: snapshot.data!),
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
        title: Text(widget.title),
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
