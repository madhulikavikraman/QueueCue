import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../core/qq.dart';
import '../db/db.dart';

Response jsonOk(Object? body, {int status = 200}) => Response(status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store'});

Future<Map<String, dynamic>> readJson(Request r) async {
  final s = await r.readAsString();
  if (s.trim().isEmpty) return {};
  try {
    final j = jsonDecode(s);
    if (j is Map<String, dynamic>) return j;
  } catch (_) {}
  throw ApiError(400, 'Request body must be JSON.');
}

String? studentToken(Request r) =>
    r.headers['x-student-token'] ?? r.url.queryParameters['st'];
String? boothKey(Request r) => r.headers['x-booth-key'] ?? r.url.queryParameters['key'];
String? orgKey(Request r) => r.headers['x-org-key'] ?? r.url.queryParameters['org'];

Row requireStudent(QQ qq, Request r) {
  final s = qq.studentByToken(studentToken(r));
  if (s == null) throw ApiError(401, 'Not signed in on this phone. Start onboarding or pick a demo student.');
  return s;
}

/// Converts ApiError (and anything else) into a JSON error the app can show.
Middleware errorMiddleware(void Function(String) log) => (inner) => (req) async {
      try {
        return await inner(req);
      } on HijackException {
        rethrow; // WebSocket upgrade: not an error, let shelf take the socket.
      } on ApiError catch (e) {
        return jsonOk({'error': e.message, ...e.extra}, status: e.status);
      } catch (e, st) {
        log('ERROR ${req.method} ${req.requestedUri.path}: $e\n$st');
        return jsonOk({'error': 'Server error: $e'}, status: 500);
      }
    };

Middleware cors() => (inner) => (req) async {
      const h = {
        'access-control-allow-origin': '*',
        'access-control-allow-headers': 'content-type, x-student-token, x-booth-key, x-org-key',
        'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
      };
      if (req.method == 'OPTIONS') return Response.ok('', headers: h);
      final res = await inner(req);
      return res.change(headers: h);
    };

double? numOrNull(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

/// True only for requests made on the host laptop itself. Tunnel traffic
/// also arrives from 127.0.0.1, so a Cloudflare header means "remote".
bool isLocalRequest(Request r) {
  if (r.headers.containsKey('cf-connecting-ip') || r.headers.containsKey('cf-ray') || r.headers.containsKey('x-forwarded-for')) return false;
  final info = r.context['shelf.io.connection_info'];
  try {
    return (info as dynamic).remoteAddress.isLoopback as bool;
  } catch (_) {
    return true; // tests (no socket)
  }
}
