import 'package:chess_position_ocr/core/fen_from_image.dart';
import 'package:chess_position_ocr/widgets/chessboard.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
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
  String? _fen;

  void _purposeTakePhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image == null) return;
    final imageData = await image.readAsBytes();
    setState(() {
      _image = imageData;
    });
    await _predictFEN();
  }

  Future<void> _predictFEN() async {
    try {
      final fen = await predictFen(_image!);
      setState(() {
        _fen = fen;
      });
    } on Exception catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    final content = <Widget>[
      TextButton(onPressed: _purposeTakePhoto, child: const Text("Take photo")),
      if (_image != null) Image.memory(_image!, width: 200, fit: BoxFit.cover),
      if (_fen != null) Chessboard(fen: _fen!),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: isPortrait
            ? Column(
                spacing: 20,
                mainAxisAlignment: MainAxisAlignment.center,
                children: content,
              )
            : Row(
                spacing: 20,
                mainAxisAlignment: MainAxisAlignment.center,
                children: content,
              ),
      ),
    );
  }
}
