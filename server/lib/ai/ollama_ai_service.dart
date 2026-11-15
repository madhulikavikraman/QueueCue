import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'ai_service.dart';
import 'lint.dart';
import 'schemas.dart';

/// Loads prompt files (one per task) and fills {{PLACEHOLDERS}}.
class PromptStore {
  final String dir;
  final Map<String, String> _cache = {};
  PromptStore(this.dir);

  String raw(String name) => _cache.putIfAbsent(
      name, () => File(p.join(dir, '$name.md')).readAsStringSync());

  /// Returns [system, user].
  List<String> build(String name, Map<String, String> vars) {
    var t = raw(name);
    final all = {
      'GROUNDING': raw('_grounding').trim(),
      'BANNED': bannedPhrases.join(', '),
      ...vars,
    };
    for (final e in all.entries) {
      t = t.replaceAll('{{${e.key}}}', e.value);
    }
    final si = t.indexOf('SYSTEM:');
    final ui = t.indexOf('USER:');
    if (si < 0 || ui < 0) return ['', t];
    return [t.substring(si + 7, ui).trim(), t.substring(ui + 5).trim()];
  }
}

class OllamaAiService implements AiService {
  final String baseUrl;
  final String model;
  final PromptStore prompts;
  final Duration timeout;
  final void Function(String)? log;

  /// Progress hook for the pitch pipeline (jobs run one at a time).
  void Function(String step)? onStep;

  OllamaAiService(
      {required this.baseUrl,
      required this.model,
      required this.prompts,
      this.timeout = const Duration(seconds: 240),
      this.log});

  @override
  String get name => 'ollama:$model';

  /// Health check: is Ollama up and is the model pulled?
  static Future<({bool up, bool hasModel, List<String> models})> check(
      String baseUrl, String model) async {
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 2));
      if (r.statusCode != 200) return (up: false, hasModel: false, models: <String>[]);
      final ms = [
        for (final m in (jsonDecode(r.body)['models'] as List? ?? []))
          (m['name'] ?? m['model']).toString()
      ];
      final has = ms.any((m) => m == model || m == '$model:latest' || m.startsWith('$model'));
      return (up: true, hasModel: has, models: ms);
    } catch (_) {
      return (up: false, hasModel: false, models: <String>[]);
    }
  }

  Object? _think(String task) {
    if (model.startsWith('gpt-oss')) {
      return task.startsWith('pitch') ? 'medium' : 'low';
    }
    // qwen3: thinking improves pitch drafting and critique; skip for extraction.
    if (model.startsWith('qwen3')) {
      return task == 'pitch_draft' || task == 'pitch_critic' || task == 'pitch_rewrite';
    }
    return null;
  }

  /// Structured call: JSON schema in `format`, validate, retry once with the
  /// validation errors, then throw AiFailure with a clear message.
  Future<Map<String, dynamic>> call(String task, Map<String, String> vars,
      {double temperature = 0.3}) async {
    final schema = Schemas.all[task]!;
    final msgs = prompts.build(task, vars);
    var messages = <Map<String, String>>[
      if (msgs[0].isNotEmpty) {'role': 'system', 'content': msgs[0]},
      {'role': 'user', 'content': msgs[1]},
    ];
    String lastErr = '';
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final body = <String, Object?>{
          'model': model,
          'messages': messages,
          'format': schema,
          'stream': false,
          'options': {'temperature': temperature, 'num_ctx': 8192},
        };
        final th = _think(task);
        if (th != null) body['think'] = th;
        final r = await http
            .post(Uri.parse('$baseUrl/api/chat'),
                headers: {'content-type': 'application/json'}, body: jsonEncode(body))
            .timeout(timeout);
        if (r.statusCode != 200) {
          lastErr = 'Ollama HTTP ${r.statusCode}: ${r.body.length > 200 ? r.body.substring(0, 200) : r.body}';
          continue;
        }
        final content = (jsonDecode(utf8.decode(r.bodyBytes))['message']?['content'] ?? '') as String;
        final Object? parsed;
        try {
          parsed = jsonDecode(content);
        } catch (_) {
          lastErr = 'Model returned invalid JSON';
          messages = [
            ...messages,
            {'role': 'assistant', 'content': content},
            {'role': 'user', 'content': 'That was not valid JSON. Return only JSON matching the schema.'}
          ];
          continue;
        }
        final errs = validateJson(parsed, schema.cast<String, Object?>());
        if (errs.isEmpty) return (parsed as Map).cast<String, dynamic>();
        lastErr = 'Schema check failed: ${errs.take(3).join('; ')}';
        messages = [
          ...messages,
          {'role': 'assistant', 'content': content},
          {'role': 'user', 'content': 'Fix these problems and return the full JSON again: ${errs.join('; ')}'}
        ];
      } on TimeoutException {
        lastErr = 'Local model timed out after ${timeout.inSeconds}s';
      } on SocketException {
        throw AiFailure('Ollama is not running at $baseUrl');
      } catch (e) {
        lastErr = '$e';
      }
    }
    log?.call('AI $task failed: $lastErr');
    throw AiFailure('Local AI could not complete "$task": $lastErr');
  }

  @override
  Future<Map<String, dynamic>> parseResume(ResumeCtx r) =>
      call('resume_parse', {'LABEL': r.label, 'RESUME': r.blindText}, temperature: 0.1);

  @override
  Future<Map<String, dynamic>> voiceProfile(String transcript, List<String> answers) =>
      call('voice_profile', {'TRANSCRIPT': transcript, 'ANSWERS': answers.join('\n')},
          temperature: 0.2);

  /// Blind scoring, twice, with the role list in two different orders; average.
  @override
  Future<Map<String, dynamic>> boothFit(StudentCtx s, BoothCtx b) async {
    String resumesText() => [
          for (final r in s.resumes) 'RESUME "${r.label}":\n${r.blindText}\n'
        ].join('\n');
    Future<Map<String, dynamic>> run(bool reversed) => call('booth_fit', {
          'BOOTH_NAME': b.name,
          'BOOTH_CATEGORY': b.category,
          'BOOTH_ABOUT': b.about,
          'ROLES': b.rolesText(reversed: reversed),
          'RESUMES': resumesText(),
        }, temperature: 0.1);
    final a = await run(false);
    final c = await run(true);
    double bestOf(Map<String, dynamic> m) => (m['scores'] as List)
        .map((x) => (x['fit'] as num).toDouble())
        .fold<double>(0, (p, v) => v > p ? v : p);
    double scoreFor(Map<String, dynamic> m, String label) {
      for (final x in (m['scores'] as List)) {
        if ((x['resume_label'] as String).toLowerCase() == label.toLowerCase()) {
          return (x['fit'] as num).toDouble();
        }
      }
      return bestOf(m);
    }

    // Average per resume across both orders; choose the best average.
    String bestLabel = a['best_resume_label'] as String;
    double best = -1;
    for (final r in s.resumes) {
      final avg = (scoreFor(a, r.label) + scoreFor(c, r.label)) / 2;
      if (avg > best) {
        best = avg;
        bestLabel = r.label;
      }
    }
    return {
      'fit': (best / 100).clamp(0.0, 1.0),
      'fit_a': scoreFor(a, bestLabel) / 100,
      'fit_b': scoreFor(c, bestLabel) / 100,
      'resume_label': bestLabel,
      'reason': a['reason'],
      'resume_reason': a['resume_reason'],
      'matched_roles': a['matched_roles'],
      'source': 'live',
    };
  }

  @override
  Future<Map<String, dynamic>> pitch(StudentCtx s, BoothCtx b,
      {String variant = 'default', String? resumeLabel, String? excludeProject}) async {
    final label = resumeLabel ?? s.defaultResume.label;
    // Step 2: Pitch Facts
    onStep?.call('Picking the facts that matter for ${b.name}');
    final facts = await call('pitch_facts', {
      'BOOTH': b.asText,
      'RESUME_LABEL': label,
      'STUDENT': s.materialsText(focusLabel: label) + '\nVOICE PROFILE:\n${s.voiceText()}',
      'EXCLUDE': excludeProject == null
          ? ''
          : '\nDo NOT use the project "$excludeProject"; pick a different one.\n',
    }, temperature: 0.2);

    final variantText = switch (variant) {
      'more_like_me' =>
        'VARIANT: "More like me". Re-read the Voice Profile. Loosen the structure: use their rhythm and their phrases, even if it is less tidy. It should sound like they are talking to a person, not presenting.',
      'shorter' =>
        'VARIANT: "Shorter". 40 to 55 words. Keep the one concrete detail and the role connection; cut everything else.',
      'different_project' =>
        'VARIANT: "Different project". Lead with a different project than "$excludeProject".',
      _ => '',
    };
    final minW = variant == 'shorter' ? 35 : 50;
    final maxW = variant == 'shorter' ? 60 : 85;
    final vars = {
      'VOICE': s.voiceText(),
      'EDITS': s.editsText(),
      'FACTS': const JsonEncoder.withIndent('  ').convert(facts),
      'FIRST_NAME': s.firstName,
      'DEGREE': s.degree,
      'MAJOR': s.major,
      'BOOTH_NAME': b.name,
      'VARIANT': variantText,
    };
    // Step 3: Draft
    onStep?.call('Drafting in your voice');
    var draft = await call('pitch_draft', vars,
        temperature: variant == 'more_like_me' ? 0.8 : 0.6);

    // Step 4: Critic (separate prompt) + deterministic lint. Max 2 rewrites.
    Map<String, dynamic>? critic;
    var rewrites = 0;
    for (;;) {
      final lint = lintText(draft['pitch'] as String,
          question: draft['question'] as String, minWords: minW, maxWords: maxW);
      onStep?.call('Critic pass${rewrites > 0 ? ' (after rewrite $rewrites)' : ''}: checking for generic or unsupported lines');
      critic = await call('pitch_critic', {
        'STUDENT': s.materialsText(focusLabel: label),
        'VOICE': s.voiceText(),
        'BOOTH': b.asText,
        'PITCH': draft['pitch'] as String,
        'QUESTION': draft['question'] as String,
      }, temperature: 0.1);
      final scoresOk = (critic['specificity'] as num) >= 4 &&
          (critic['sounds_like_them'] as num) >= 4 &&
          (critic['believability'] as num) >= 4;
      final pass = critic['verdict'] == 'pass' && scoresOk && lint.ok;
      if (pass || rewrites >= 2) break;
      rewrites++;
      onStep?.call('Rewriting: draft $rewrites of 2 failed review');
      final feedback = [
        ...lint.issues,
        if ((critic['fix_instructions'] as String).isNotEmpty) critic['fix_instructions'],
        for (final u in (critic['untraceable'] as List)) 'Remove or source: $u',
        for (final u in (critic['praise'] as List)) 'Remove company praise: $u',
        for (final u in (critic['self_praise'] as List)) 'Remove self-praise: $u',
        if (!scoresOk)
          'Scores: specificity ${critic['specificity']}, sounds-like-them ${critic['sounds_like_them']}, believability ${critic['believability']}. Raise all to 4+.',
      ].join('\n- ');
      draft = await call('pitch_rewrite', {
        'VOICE': s.voiceText(),
        'FACTS': vars['FACTS']!,
        'PITCH': draft['pitch'] as String,
        'QUESTION': draft['question'] as String,
        'FEEDBACK': '- $feedback',
      }, temperature: 0.5);
    }
    return {
      ...draft,
      'facts': facts,
      'critic': critic,
      'rewrites': rewrites,
      'resume_label': label,
      'variant': variant,
      'source': 'live',
    };
  }

  @override
  Future<Map<String, dynamic>> dropNote(StudentCtx s, BoothCtx b, ResumeCtx r) =>
      call('drop_note', {
        'VOICE': s.voiceText(),
        'RESUME_LABEL': r.label,
        'RESUME': r.blindText,
        'BOOTH': b.asText,
      }, temperature: 0.5);

  @override
  Future<Map<String, dynamic>> recruiterSummary(StudentCtx s, BoothCtx b, ResumeCtx r) =>
      call('recruiter_summary', {'ROLES': b.rolesText(), 'RESUME': r.blindText},
          temperature: 0.1);

  @override
  Future<Map<String, dynamic>> followUpEmail(StudentCtx s, BoothCtx b,
          {required String note, required String recruiterName, ResumeCtx? resume}) =>
      call('followup_email', {
        'VOICE': s.voiceText(),
        'FIRST_NAME': s.firstName,
        'RECRUITER': recruiterName,
        'BOOTH_NAME': b.name,
        'NOTE': note,
        'RESUME_LABEL': (resume ?? s.defaultResume).label,
        'RESUME': (resume ?? s.defaultResume).blindText,
      }, temperature: 0.6);
}
