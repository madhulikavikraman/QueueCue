import 'dart:convert';
import 'dart:io';

import 'ai_service.dart';
import 'lint.dart';
import 'offline_ai.dart';
import 'ollama_ai_service.dart';

/// Returns precomputed results from assets/demo/ai_cache.json, keyed by demo
/// persona. Misses fall back to the deterministic OfflineAi.
class CachedAiService implements AiService {
  final Map<String, dynamic> entries;
  final OfflineAi offline = OfflineAi();
  final String path;

  CachedAiService._(this.entries, this.path);

  static CachedAiService load(String path) {
    final f = File(path);
    if (!f.existsSync()) return CachedAiService._({}, path);
    final j = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return CachedAiService._(
        (j['entries'] as Map<String, dynamic>?) ?? <String, dynamic>{}, path);
  }

  @override
  String get name => 'cache';

  Map<String, dynamic>? get(String key) {
    final v = entries[key];
    if (v is Map) return Map<String, dynamic>.from(v)..['source'] = 'cache';
    return null;
  }

  String? _p(StudentCtx s) => s.persona;

  @override
  Future<Map<String, dynamic>> parseResume(ResumeCtx r) => offline.parseResume(r);

  @override
  Future<Map<String, dynamic>> voiceProfile(String transcript, List<String> answers) =>
      offline.voiceProfile(transcript, answers);

  @override
  Future<Map<String, dynamic>> boothFit(StudentCtx s, BoothCtx b) async =>
      (_p(s) == null ? null : get('fit:${_p(s)}:${b.id}')) ?? await offline.boothFit(s, b);

  @override
  Future<Map<String, dynamic>> pitch(StudentCtx s, BoothCtx b,
      {String variant = 'default', String? resumeLabel, String? excludeProject}) async {
    Map<String, dynamic>? hit;
    if (_p(s) != null) {
      hit = get('pitch:${_p(s)}:${b.id}:$variant');
      // Cached "different project" must actually differ from the one shown.
      if (hit != null && variant == 'different_project' && hit['project'] == excludeProject) {
        hit = null;
      }
      if (hit == null && (variant == 'more_like_me' || variant == 'shorter')) {
        final base = get('pitch:${_p(s)}:${b.id}:default');
        if (base != null) {
          hit = base
            ..['notice'] = 'No cached "$variant" version for this booth. Turn on live AI to regenerate.';
        }
      }
    }
    if (hit == null) {
      return offline.pitch(s, b,
          variant: variant, resumeLabel: resumeLabel, excludeProject: excludeProject);
    }
    final sources = {
      for (final x in s.resumes) 'Resume "${x.label}"': x.blindText,
      if (s.transcript != null) 'Voice Profile': '${s.transcript} ${s.answers.join(' ')}',
      'Employer data': b.asText,
    };
    hit['trace'] ??= traceSentences(hit['pitch'] as String, sources);
    hit['variant'] = variant;
    return hit;
  }

  @override
  Future<Map<String, dynamic>> dropNote(StudentCtx s, BoothCtx b, ResumeCtx r) async =>
      (_p(s) == null ? null : get('note:${_p(s)}:${b.id}:${r.label}')) ??
      await offline.dropNote(s, b, r);

  @override
  Future<Map<String, dynamic>> recruiterSummary(StudentCtx s, BoothCtx b, ResumeCtx r) async =>
      (_p(s) == null ? null : get('summary:${_p(s)}:${b.id}:${r.label}')) ??
      await offline.recruiterSummary(s, b, r);

  @override
  Future<Map<String, dynamic>> followUpEmail(StudentCtx s, BoothCtx b,
      {required String note, required String recruiterName, ResumeCtx? resume}) async {
    final hit = _p(s) == null ? null : get('email:${_p(s)}:${b.id}');
    // A cached email is only valid for the note it was written from.
    if (hit != null && _similar(note, hit['for_note'] as String? ?? '') >= 0.6) {
      return hit..remove('for_note');
    }
    return offline.followUpEmail(s, b, note: note, recruiterName: recruiterName, resume: resume);
  }

  static double _similar(String a, String b) {
    Set<String> t(String s) =>
        s.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 2).toSet();
    final x = t(a), y = t(b);
    if (x.isEmpty || y.isEmpty) return 0;
    return x.intersection(y).length / (x.length > y.length ? x.length : y.length);
  }
}

/// Chooses live vs cached per the organizer's toggle, and degrades gracefully:
/// if the live model fails, the cached/offline result is returned with a clear
/// `notice` the app shows to the user.
class AiRouter implements AiService {
  final OllamaAiService live;
  CachedAiService cached;
  bool Function() useLive;

  AiRouter({required this.live, required this.cached, required this.useLive});

  @override
  String get name => useLive() ? live.name : cached.name;

  Future<Map<String, dynamic>> _run(Future<Map<String, dynamic>> Function(AiService) f) async {
    if (!useLive()) return f(cached);
    try {
      return await f(live);
    } on AiFailure catch (e) {
      final r = await f(cached);
      return {...r, 'notice': '${e.message}. Showing a ${r['source'] == 'cache' ? 'cached' : 'offline'} result instead.'};
    }
  }

  @override
  Future<Map<String, dynamic>> parseResume(ResumeCtx r) => _run((a) => a.parseResume(r));
  @override
  Future<Map<String, dynamic>> voiceProfile(String t, List<String> a) =>
      _run((x) => x.voiceProfile(t, a));
  @override
  Future<Map<String, dynamic>> boothFit(StudentCtx s, BoothCtx b) => _run((a) => a.boothFit(s, b));
  @override
  Future<Map<String, dynamic>> pitch(StudentCtx s, BoothCtx b,
          {String variant = 'default', String? resumeLabel, String? excludeProject}) =>
      _run((a) => a.pitch(s, b,
          variant: variant, resumeLabel: resumeLabel, excludeProject: excludeProject));
  @override
  Future<Map<String, dynamic>> dropNote(StudentCtx s, BoothCtx b, ResumeCtx r) =>
      _run((a) => a.dropNote(s, b, r));
  @override
  Future<Map<String, dynamic>> recruiterSummary(StudentCtx s, BoothCtx b, ResumeCtx r) =>
      _run((a) => a.recruiterSummary(s, b, r));
  @override
  Future<Map<String, dynamic>> followUpEmail(StudentCtx s, BoothCtx b,
          {required String note, required String recruiterName, ResumeCtx? resume}) =>
      _run((a) => a.followUpEmail(s, b, note: note, recruiterName: recruiterName, resume: resume));
}
