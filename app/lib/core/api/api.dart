import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final int status;
  final String message;
  final Json data;
  ApiException(this.status, this.message, [this.data = const {}]);
  @override
  String toString() => message;
}

/// The host laptop serves both this web app and the API, so the API lives at
/// the page's own origin. For `flutter run`, pass --dart-define=API=http://localhost:8080
String apiBase() {
  const fromEnv = String.fromEnvironment('API');
  if (fromEnv.isNotEmpty) return fromEnv;
  final b = Uri.base;
  if (b.scheme.startsWith('http')) return b.origin;
  return 'http://localhost:8080';
}

class Api {
  final String base;
  String? studentToken;
  final http.Client _c = http.Client();
  Api(this.base);

  Map<String, String> _h(Map<String, String>? extra) => {
        'content-type': 'application/json',
        if (studentToken != null) 'x-student-token': studentToken!,
        ...?extra,
      };

  Future<Json> _send(String method, String path, {Object? body, Map<String, String>? headers}) async {
    final uri = Uri.parse('$base$path');
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(_h(headers));
      if (body != null) req.body = jsonEncode(body);
      r = await http.Response.fromStream(await _c.send(req)).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw ApiException(0, 'The host laptop took too long to answer. Check the Wi-Fi and try again.');
    } catch (e) {
      throw ApiException(0, 'Cannot reach the host laptop. Check you are on the fair link.');
    }
    Json j = {};
    if (r.body.isNotEmpty) {
      try {
        final d = jsonDecode(utf8.decode(r.bodyBytes));
        if (d is Map<String, dynamic>) j = d;
      } catch (_) {}
    }
    if (r.statusCode >= 400) {
      throw ApiException(r.statusCode, (j['error'] as String?) ?? 'Request failed (${r.statusCode}).', j);
    }
    return j;
  }

  Future<Json> get(String path, {Map<String, String>? headers}) => _send('GET', path, headers: headers);
  Future<Json> post(String path, [Object? body, Map<String, String>? headers]) =>
      _send('POST', path, body: body ?? const {}, headers: headers);
  Future<Json> put(String path, Object body) => _send('PUT', path, body: body);
  Future<Json> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<Json> delete(String path) => _send('DELETE', path);

  Future<List<int>> bytesOf(String url) async => (await _c.get(Uri.parse(url))).bodyBytes;

  /// Opens a file download (CSV/ZIP/PDF) in a new tab.
  Future<void> openUrl(String pathOrUrl) async {
    final u = pathOrUrl.startsWith('http') || pathOrUrl.startsWith('mailto:') ? pathOrUrl : '$base$pathOrUrl';
    await launchUrl(Uri.parse(u), webOnlyWindowName: '_blank');
  }

  String wsUrl() {
    final u = Uri.parse(base);
    return u.replace(scheme: u.scheme == 'https' ? 'wss' : 'ws', path: '/ws').toString();
  }
}

final apiProvider = Provider<Api>((ref) => Api(apiBase()));

/// Student session (token stored on this phone).
class Session extends Notifier<String?> {
  static const _k = 'qq_student_token';
  @override
  String? build() => null;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final t = p.getString(_k);
    ref.read(apiProvider).studentToken = t;
    state = t;
  }

  Future<void> set(String? token) async {
    final p = await SharedPreferences.getInstance();
    if (token == null) {
      await p.remove(_k);
    } else {
      await p.setString(_k, token);
    }
    ref.read(apiProvider).studentToken = token;
    state = token;
  }
}

final sessionProvider = NotifierProvider<Session, String?>(Session.new);

/// Recruiter session on this device: which booth, and its key.
typedef RecruiterAuth = ({String boothId, String key, String name, String company});

class RecruiterSession extends Notifier<RecruiterAuth?> {
  static const _k = 'qq_recruiter';
  @override
  RecruiterAuth? build() => null;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_k);
    if (v == null) return;
    final j = jsonDecode(v) as Map<String, dynamic>;
    state = (boothId: j['booth_id'] as String, key: j['key'] as String, name: j['name'] as String? ?? '', company: j['company'] as String? ?? '');
  }

  Future<void> set(RecruiterAuth? a) async {
    final p = await SharedPreferences.getInstance();
    if (a == null) {
      await p.remove(_k);
    } else {
      await p.setString(_k, jsonEncode({'booth_id': a.boothId, 'key': a.key, 'name': a.name, 'company': a.company}));
    }
    state = a;
  }
}

final recruiterProvider = NotifierProvider<RecruiterSession, RecruiterAuth?>(RecruiterSession.new);

/// Small key-value store for recruiter / organizer keys on this device.
class Prefs {
  static Future<String?> get(String k) async => (await SharedPreferences.getInstance()).getString(k);
  static Future<void> set(String k, String v) async => (await SharedPreferences.getInstance()).setString(k, v);
}
