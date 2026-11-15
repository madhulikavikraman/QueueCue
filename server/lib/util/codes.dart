import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Rotating personal QR for students and static join tokens for booths.
class Codes {
  final String secret;
  static const windowSec = 30;
  Codes(this.secret);

  static String randomToken([int bytes = 18]) {
    final r = Random.secure();
    final b = List<int>.generate(bytes, (_) => r.nextInt(256));
    return base64Url.encode(b).replaceAll('=', '');
  }

  String _hmac(String msg, [int len = 12]) {
    final h = Hmac(sha256, utf8.encode(secret)).convert(utf8.encode(msg));
    return h.toString().substring(0, len);
  }

  static int windowAt(int ms) => ms ~/ 1000 ~/ windowSec;

  /// `qq:s:<studentId>:<window>:<mac>`. Refreshes every 30 s. A screenshot is
  /// useless after at most ~60 s (current + previous window accepted).
  String studentCode(String studentId, int nowMs) {
    final w = windowAt(nowMs);
    return 'qq:s:$studentId:$w:${_hmac('s|$studentId|$w')}';
  }

  int secondsLeft(int nowMs) => windowSec - ((nowMs ~/ 1000) % windowSec);

  /// Returns the student id when the code is valid right now, else null.
  String? verifyStudentCode(String code, int nowMs) {
    final parts = code.trim().split(':');
    if (parts.length != 5 || parts[0] != 'qq' || parts[1] != 's') return null;
    final sid = parts[2];
    final w = int.tryParse(parts[3]);
    if (w == null) return null;
    final cur = windowAt(nowMs);
    if (w != cur && w != cur - 1) return null;
    if (_hmac('s|$sid|$w') != parts[4]) return null;
    return sid;
  }

  /// Static token printed in the booth QR. It only lets a student join a line
  /// or drop a resume. It never counts as a conversation.
  String boothJoinToken(String boothId) => _hmac('b|$boothId', 10);
  bool verifyBoothJoin(String boothId, String? token) =>
      token != null && token == boothJoinToken(boothId);

  /// Friend-add code (static per student, harmless to share).
  String friendCode(String studentId) => 'qq:f:$studentId:${_hmac('f|$studentId', 8)}';
  String? verifyFriendCode(String code) {
    final p = code.trim().split(':');
    if (p.length != 4 || p[0] != 'qq' || p[1] != 'f') return null;
    return _hmac('f|${p[2]}', 8) == p[3] ? p[2] : null;
  }
}
