import 'dart:io';
import 'package:queuecue_server/app.dart';
import 'package:queuecue_server/config.dart';

Future<void> main() async {
  final qq = await buildQQ(Config.load(), dbPath: ':memory:');
  final live = qq.ai.live..onStep = (m) => stdout.writeln('  step: $m');
  final ctx = qq.studentCtx('stu-viktor');
  final b = qq.boothCtx(qq.booth('lumen'));
  final sw = Stopwatch()..start();
  final f = await live.boothFit(ctx, b);
  stdout.writeln('FIT ${(f['fit'] as num).toStringAsFixed(2)} (a ${f['fit_a']}, b ${f['fit_b']}) resume=${f['resume_label']} | ${f['reason']}  [${sw.elapsed.inSeconds}s]');
  final p = await live.pitch(ctx, b, resumeLabel: 'AI/ML');
  stdout.writeln('PITCH (${(p['pitch'] as String).split(' ').length} words, rewrites ${p['rewrites']}) [${sw.elapsed.inSeconds}s]:\n${p['pitch']}\nQ: ${p['question']}');
  final c = p['critic'] as Map;
  stdout.writeln('CRITIC: specificity ${c['specificity']} sounds-like ${c['sounds_like_them']} believability ${c['believability']} verdict ${c['verdict']}');
  exit(0);
}
