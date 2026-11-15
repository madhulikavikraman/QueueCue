import 'dart:io';

import 'package:qr/qr.dart';

/// Prints a scannable QR code in the terminal: dart run bin/qr.dart <text>
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run bin/qr.dart <text>');
    exit(64);
  }
  final img = QrImage(QrCode.fromData(data: args.join(' '), errorCorrectLevel: QrErrorCorrectLevel.L));
  final n = img.moduleCount;
  bool dark(int r, int c) => r >= 0 && c >= 0 && r < n && c < n && img.isDark(r, c);
  final b = StringBuffer();
  // Two rows per line with half blocks; white quiet zone of 2 modules.
  for (var r = -2; r < n + 2; r += 2) {
    for (var c = -2; c < n + 2; c++) {
      final top = dark(r, c), bot = dark(r + 1, c);
      b.write(top && bot ? ' ' : top ? '▄' : bot ? '▀' : '█');
    }
    b.writeln();
  }
  stdout.write(b.toString());
}
