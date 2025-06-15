import 'package:chess_vectors_flutter/chess_vectors_flutter.dart';
import 'package:flutter/material.dart';
import 'package:wp_chessboard/wp_chessboard.dart';

class Chessboard extends StatelessWidget {
  final String fen;
  const Chessboard({super.key, required this.fen});

  @override
  Widget build(BuildContext context) {
    return WPChessboard(
      size: 300,
      controller: WPChessboardController(
        initialFen: fen,
      ),
      squareBuilder: (SquareInfo info) {
        return Container(
          color: (info.file + info.rank) % 2 == 0
              ? Colors.orangeAccent
              : Colors.brown,
        );
      },
      pieceMap: PieceMap(
        K: (size) => WhiteKing(size: size),
        Q: (size) => WhiteQueen(size: size),
        B: (size) => WhiteBishop(size: size),
        N: (size) => WhiteKnight(size: size),
        R: (size) => WhiteRook(size: size),
        P: (size) => WhitePawn(size: size),
        k: (size) => BlackKing(size: size),
        q: (size) => BlackQueen(size: size),
        b: (size) => BlackBishop(size: size),
        n: (size) => BlackKnight(size: size),
        r: (size) => BlackRook(size: size),
        p: (size) => BlackPawn(size: size),
      ),
    );
  }
}
