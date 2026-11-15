import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'codes.dart';

/// Salted SHA-256. Fine for a local hackathon host; nothing leaves the laptop.
String hashPassword(String pw) {
  final salt = Codes.randomToken(12);
  return 'sha256:$salt:${sha256.convert(utf8.encode('$salt:$pw'))}';
}

/// Accepts hashed values and the plain demo passwords in the seed.
bool checkPassword(String pw, String? stored) {
  if (stored == null || stored.isEmpty) return false;
  if (!stored.startsWith('sha256:')) return pw == stored;
  final parts = stored.split(':');
  if (parts.length != 3) return false;
  return sha256.convert(utf8.encode('${parts[1]}:$pw')).toString() == parts[2];
}
