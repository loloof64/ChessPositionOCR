import 'package:chess_position_ocr/screens/board_photo_to_isolated_board_photo.dart';
import 'package:chess_position_ocr/screens/board_photo_to_position.dart';
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

class MainWidget extends StatelessWidget {
  const MainWidget({super.key});

  void _goToOCRPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BoardPhotoToPosition()),
    );
  }

  void _goToBoardIsolationPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BoardPhotoToIsolatedBoardPhoto(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chess OCR experiment')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => _goToOCRPage(context),
              child: Text("Go to OCR page"),
            ),
            TextButton(
              onPressed: () => _goToBoardIsolationPage(context),
              child: Text("Go to board isolation page"),
            ),
          ],
        ),
      ),
    );
  }
}
