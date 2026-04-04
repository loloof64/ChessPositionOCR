import 'package:chess_position_ocr/core/chess_recognizer.dart';
import 'package:chess_position_ocr/screens/board_photo_ocr.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
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
      home: const MainWidget(),
    );
  }
}

class MainWidget extends StatefulWidget {
  const MainWidget({super.key});

  @override
  State<MainWidget> createState() => _MainWidgetState();
}

class _MainWidgetState extends State<MainWidget> {
  ChessRecognizer _chessRecognizer = ChessRecognizer();
  late Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadChessRecognizer();
  }

  Future<void> _loadChessRecognizer() async {
    await _chessRecognizer.load();
  }

  @override
  void dispose() {
    _chessRecognizer.dispose();
    super.dispose();
  }

  void _goToBoardIsolationPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            BoardPhotoOCRPage(chessRecognizer: _chessRecognizer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Chess OCR experiment')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Chess OCR experiment')),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _goToBoardIsolationPage(context),
                  child: const Text("Go to OCR page"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
