import 'dart:async';
import 'dart:io';

import 'package:queuecue_server/core/close_audit.dart';

import 'package:queuecue_server/ai/ollama_ai_service.dart';
import 'package:queuecue_server/app.dart';
import 'package:queuecue_server/config.dart';
import 'package:queuecue_server/seed/seeder.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main(List<String> args) async {
  final cfg = Config.load();
  final qq = await buildQQ(cfg);
  if (args.contains('--reset')) {
    await Seeder(qq).run();
    stdout.writeln('Demo data reset to seed.');
  }
  if (args.contains('--live')) qq.db.setMeta('ai_live', '1');
  if (args.contains('--cached')) qq.db.setMeta('ai_live', '0');

  final handler = const Pipeline()
      .addMiddleware(logRequests(logger: (msg, isError) {
        if (isError || msg.contains('/api/') && !msg.contains('GET')) stdout.writeln(msg);
      }))
      .addHandler(buildHandler(qq));
  final server = await io.serve(handler, InternetAddress.anyIPv4, cfg.port);
  server.autoCompress = true;

  final o = await OllamaAiService.check(cfg.ollamaUrl, cfg.model);
  final whisper = await qq.whisper.available();
  stdout.writeln('''
QueueCue server on http://localhost:${server.port}
  AI mode:   ${qq.aiLive ? 'LIVE (${cfg.model})' : 'CACHED (Demo Mode). Toggle on /organizer.'}
  Ollama:    ${o.up ? (o.hasModel ? 'up, ${cfg.model} ready' : 'up, but ${cfg.model} not pulled (ollama pull ${cfg.model})') : 'not running (cached mode still works)'}
  whisper:   ${whisper ? 'ready' : 'not set up (typed answers still work)'}
  Organizer: http://localhost:${server.port}/organizer?org=${cfg.organizerKey}
''');
  // Real fairs close themselves at the scheduled end (line credit + Fair Play).
  // Off in Demo Mode so a demo never closes on its own.
  Timer.periodic(const Duration(seconds: 60), (_) {
    try {
      final f = qq.fair();
      if (!qq.demoMode && f['status'] == 'open' && qq.clock() >= (f['ends_at'] as int)) {
        stdout.writeln(qq.closeFair()['message']);
      }
    } catch (_) {}
  });
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    qq.db.raw.dispose();
    exit(0);
  });
}
