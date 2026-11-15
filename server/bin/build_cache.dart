import 'dart:convert';
import 'dart:io';

import 'package:queuecue_server/ai/ollama_ai_service.dart';
import 'package:queuecue_server/app.dart';
import 'package:queuecue_server/config.dart';

/// Regenerates assets/demo/ai_cache.json by running the LIVE local model on
/// the seed personas. Run before the demo (takes a while on a laptop):
///   dart run bin/build_cache.dart              # all personas x all booths
///   dart run bin/build_cache.dart northwind    # only some booths
Future<void> main(List<String> args) async {
  final cfg = Config.load();
  final o = await OllamaAiService.check(cfg.ollamaUrl, cfg.model);
  if (!o.up || !o.hasModel) {
    stderr.writeln('Ollama must be running with ${cfg.model} pulled (ollama pull ${cfg.model}).');
    exit(1);
  }
  final qq = await buildQQ(cfg, dbPath: ':memory:');
  final live = qq.ai.live;
  final cacheFile = File(cfg.cachePath);
  final existing = cacheFile.existsSync()
      ? (jsonDecode(cacheFile.readAsStringSync())['entries'] as Map<String, dynamic>)
      : <String, dynamic>{};
  final out = Map<String, dynamic>.from(existing);
  final personas = ['viktor', 'hermione', 'percy'];
  final booths = qq.booths().where((b) => args.isEmpty || args.contains(b['id'])).toList();
  final sw = Stopwatch()..start();
  void save() => cacheFile.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
        'version': 1,
        'model': cfg.model,
        'generated_at': DateTime.now().toIso8601String(),
        'entries': out,
      }));
  for (final p in personas) {
    final ctx = qq.studentCtx('stu-$p');
    for (final b in booths) {
      final bc = qq.boothCtx(b);
      final id = b['id'];
      stdout.writeln('[${sw.elapsed.inMinutes}m] $p @ $id: fit');
      final f = await live.boothFit(ctx, bc);
      out['fit:$p:$id'] = f..remove('source');
      if ((f['fit'] as num) < 0.5) {
        save();
        continue; // pitches only where they matter
      }
      String? prevProject;
      for (final v in ['default', 'more_like_me', 'shorter', 'different_project']) {
        stdout.writeln('[${sw.elapsed.inMinutes}m] $p @ $id: pitch $v');
        final pr = await live.pitch(ctx, bc,
            variant: v, resumeLabel: f['resume_label'] as String, excludeProject: prevProject);
        if (v == 'default') prevProject = pr['project'] as String?;
        out['pitch:$p:$id:$v'] = pr..remove('source');
      }
      final r = ctx.resumeByLabel(f['resume_label'] as String) ?? ctx.defaultResume;
      out['note:$p:$id:${r.label}'] = (await live.dropNote(ctx, bc, r))..remove('source');
      out['summary:$p:$id:${r.label}'] = (await live.recruiterSummary(ctx, bc, r))..remove('source');
      final t = existing['transcript:$p:$id'] ?? existing['transcript:$p:any'];
      if (t != null) {
        final e = await live.followUpEmail(ctx, bc,
            note: t['text'] as String, recruiterName: (b['recruiter_name'] ?? '') as String, resume: r);
        out['email:$p:$id'] = {...e..remove('source'), 'for_note': t['text']};
      }
      save();
    }
  }
  save();
  stdout.writeln('Wrote ${out.length} entries to ${cfg.cachePath} in ${sw.elapsed.inMinutes} min.');
  exit(0);
}
