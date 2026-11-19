import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';

import 'ai/cached_ai_service.dart';
import 'ai/ollama_ai_service.dart';
import 'ai/transcribe.dart';
import 'config.dart';
import 'core/close_audit.dart';
import 'core/hub.dart';
import 'core/qq.dart';
import 'db/db.dart';
import 'routes/api.dart';
import 'routes/http_util.dart';
import 'seed/seeder.dart';
import 'util/codes.dart';

/// Builds the whole service. Used by bin/server.dart and by tests.
Future<QQ> buildQQ(Config cfg, {String? dbPath, int Function()? clock, bool seedIfEmpty = true}) async {
  final db = Db.open(dbPath ?? cfg.resolve(cfg.dbPath));
  var secret = db.meta('server_secret');
  if (secret == null) {
    secret = Codes.randomToken(32);
    db.setMeta('server_secret', secret);
  }
  if (db.meta('demo_mode') == null) db.setMeta('demo_mode', cfg.demoModeDefault ? '1' : '0');
  if (db.meta('ai_live') == null) db.setMeta('ai_live', cfg.aiLiveDefault ? '1' : '0');
  // Privacy: voices are never stored. Wipe any audio left by a crash.
  final audioDir = Directory(p.join(cfg.resolve(cfg.uploadsDir), 'audio'));
  if (audioDir.existsSync()) {
    for (final f in audioDir.listSync()) {
      try {
        f.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
  late QQ qq;
  final live = OllamaAiService(
      baseUrl: cfg.ollamaUrl,
      model: cfg.model,
      prompts: PromptStore(cfg.promptsDir),
      log: (m) => stderr.writeln(m));
  final router = AiRouter(
      live: live, cached: CachedAiService.load(cfg.cachePath), useLive: () => qq.aiLive);
  qq = QQ(
    db: db,
    cfg: cfg,
    codes: Codes(secret),
    ai: router,
    hub: Hub(),
    whisper: Transcriber(cfg.whisperBin, cfg.resolve(cfg.whisperModel)),
    clock: clock,
  );
  if (seedIfEmpty && db.one('SELECT 1 FROM fairs') == null) {
    await Seeder(qq).run();
  }
  _shortenCardNumbers(qq);
  // Demo data seeded hours ago looks stale (people "waiting" all night).
  final seededAt = int.tryParse(qq.db.meta('seeded_at') ?? '');
  if (qq.demoMode && seededAt != null && qq.clock() - seededAt > 3 * 3600 * 1000 && qq.db.one('SELECT 1 FROM fairs') != null) {
    final d = qq.refreshDemoTimes();
    stdout.writeln('Demo times moved forward ${(d / 60000).round()} min.');
  }
  if (qq.demoMode && await Seeder(qq).addShowcaseIfMissing()) stdout.writeln('Added the 10 showcase students.');
  // The project folder can move; re-point stored PDF paths at this uploads folder.
  final up = cfg.resolve(cfg.uploadsDir);
  for (final r in qq.db.all('SELECT id, pdf_path FROM resumes WHERE pdf_path IS NOT NULL')) {
    final old = r['pdf_path'] as String;
    if (File(old).existsSync()) continue;
    final moved = p.join(up, p.basename(old));
    if (File(moved).existsSync()) qq.db.exec('UPDATE resumes SET pdf_path=? WHERE id=?', [moved, r['id']]);
  }
  // Offline summaries are cheap: rebuild them so parser fixes apply to old data.
  for (final r in qq.db.all('SELECT booth_id, student_id, resume_id, json FROM summaries')) {
    if ((r['json'] as String).contains('"source":"offline"')) {
      qq.offlineSummary(r['booth_id'] as String, r['student_id'] as String, r['resume_id'] as String);
    }
  }
  return qq;
}

Handler buildHandler(QQ qq, {void Function(String)? log}) {
  final api = buildApi(qq);
  final ws = webSocketHandler((channel, _) => qq.hub.add(channel), pingInterval: const Duration(seconds: 20));
  final webRoot = qq.cfg.resolve(qq.cfg.webRoot);
  final hasWeb = File(p.join(webRoot, 'index.html')).existsSync();
  final static = hasWeb
      ? createStaticHandler(webRoot, defaultDocument: 'index.html')
      : (Request r) => Response.notFound('Web app not built. Run: cd app && flutter build web');

  Future<Response> spa(Request req) async {
    final res = await static(req);
    if (res.statusCode == 404 && hasWeb && !req.url.path.contains('.')) {
      // Client-side routes (/booth/x, /join/x, /organizer...) -> index.html
      final f = File(p.join(webRoot, 'index.html'));
      return Response.ok(f.readAsStringSync(),
          headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-cache'});
    }
    final path = req.url.path;
    if (path.isEmpty || path == 'index.html' || path.endsWith('service_worker.js') || path.endsWith('bootstrap.js')) {
      return res.change(headers: {'cache-control': 'no-cache'});
    }
    return res;
  }

  final cascade = Cascade().add((Request req) {
    if (req.url.path == 'ws') return ws(req);
    if (req.url.path.startsWith('api/')) return api.call(req);
    return Response.notFound('');
  }).add(spa);

  return const Pipeline()
      .addMiddleware(cors())
      .addMiddleware(errorMiddleware(log ?? (m) => stderr.writeln(m)))
      .addHandler(cascade.handler);
}

/// One-time migration: 8-digit card numbers -> 4-digit (students) and
/// 3-digit (recruiters), keeping every account and its data.
void _shortenCardNumbers(QQ qq) {
  final db = qq.db;
  const fixed = {'viktor': 1042, 'hermione': 4512, 'percy': 3307};
  final students = db.all('SELECT id, persona, number FROM students WHERE number >= 10000');
  final booths = db.all('SELECT id, number FROM booths WHERE recruiter_number >= 1000 OR recruiter_number IS NULL');
  if (students.isEmpty && booths.isEmpty) return;
  db.tx(() {
    for (final s in students) {
      final want = fixed[s['persona']];
      int n;
      if (want != null && db.one('SELECT 1 FROM students WHERE number=?', [want]) == null) {
        n = want;
      } else {
        do {
          n = 1000 + qq.rnd.nextInt(9000);
        } while (fixed.containsValue(n) || db.one('SELECT 1 FROM students WHERE number=?', [n]) != null);
      }
      db.exec('UPDATE students SET number=? WHERE id=?', [n, s['id']]);
    }
    for (final b in booths) {
      var n = 100 + (b['number'] as int) * 61 % 900;
      while (db.one('SELECT 1 FROM booths WHERE recruiter_number=? AND id<>?', [n, b['id']]) != null) {
        n = 100 + qq.rnd.nextInt(900);
      }
      db.exec('UPDATE booths SET recruiter_number=? WHERE id=?', [n, b['id']]);
    }
  });
  stdout.writeln('Shortened card numbers: ${students.length} students, ${booths.length} recruiters.');
}
