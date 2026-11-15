import 'dart:convert';

/// One interface, several implementations:
///  - OllamaAiService: live, local model.
///  - CachedAiService: precomputed results from assets/demo/ai_cache.json.
///  - OfflineAi: deterministic, grounded fallback used when the cache misses
///    or the live model is unavailable. Always labelled as such.
abstract class AiService {
  String get name;

  Future<Map<String, dynamic>> parseResume(ResumeCtx r);
  Future<Map<String, dynamic>> voiceProfile(String transcript, List<String> answers);
  Future<Map<String, dynamic>> boothFit(StudentCtx s, BoothCtx b);
  Future<Map<String, dynamic>> pitch(StudentCtx s, BoothCtx b,
      {String variant = 'default', String? resumeLabel, String? excludeProject});
  Future<Map<String, dynamic>> dropNote(StudentCtx s, BoothCtx b, ResumeCtx r);
  Future<Map<String, dynamic>> recruiterSummary(
      StudentCtx s, BoothCtx b, ResumeCtx r);
  Future<Map<String, dynamic>> followUpEmail(StudentCtx s, BoothCtx b,
      {required String note, required String recruiterName, ResumeCtx? resume});
}

class AiFailure implements Exception {
  final String message;
  AiFailure(this.message);
  @override
  String toString() => message;
}

class BoothCtx {
  final String id;
  final String name;
  final String category;
  final String about;
  final List<Map<String, dynamic>> roles;
  final String sponsors;
  final List<String> majors;
  final List<String> partialMajors;
  final bool citizenshipRequired;
  final String? recruiterName;

  BoothCtx({
    required this.id,
    required this.name,
    required this.category,
    required this.about,
    required this.roles,
    required this.sponsors,
    required this.majors,
    required this.partialMajors,
    required this.citizenshipRequired,
    this.recruiterName,
  });

  String rolesText({bool reversed = false}) {
    final rs = reversed ? roles.reversed.toList() : roles;
    return [for (final r in rs) '- ${r['title']}: ${r['desc']}'].join('\n');
  }

  String get asText => 'Name: $name\nCategory: $category\nAbout: $about\n'
      'Sponsors visas: $sponsors\n'
      'Requires US citizenship: ${citizenshipRequired ? 'yes' : 'no'}\n'
      'Roles:\n${rolesText()}';
}

class ResumeCtx {
  final String id;
  final String label;
  final String blindText;
  final bool isDefault;
  final Map<String, dynamic>? parsed;
  ResumeCtx(
      {required this.id,
      required this.label,
      required this.blindText,
      this.isDefault = false,
      this.parsed});
}

class StudentCtx {
  final String id;
  final String? persona;
  final String firstName;
  final String major;
  final String degree;
  final String workAuth;
  final List<ResumeCtx> resumes;
  final Map<String, dynamic>? voiceProfile;
  final String? transcript;
  final List<String> answers;
  final List<Map<String, dynamic>> edits;

  StudentCtx({
    required this.id,
    required this.persona,
    required this.firstName,
    required this.major,
    required this.degree,
    required this.workAuth,
    required this.resumes,
    this.voiceProfile,
    this.transcript,
    this.answers = const [],
    this.edits = const [],
  });

  bool get hasVoice => voiceProfile != null && voiceProfile!.isNotEmpty;

  ResumeCtx? resumeByLabel(String? label) {
    if (label == null) return null;
    for (final r in resumes) {
      if (r.label.toLowerCase() == label.toLowerCase()) return r;
    }
    return null;
  }

  ResumeCtx get defaultResume =>
      resumes.firstWhere((r) => r.isDefault, orElse: () => resumes.first);

  String voiceText() => hasVoice
      ? const JsonEncoder.withIndent('  ').convert(voiceProfile)
      : 'unknown (student skipped the Voice Profile; write plainly, short sentences, neutral formality, contractions ok)';

  String materialsText({String? focusLabel}) {
    final b = StringBuffer();
    for (final r in resumes) {
      b.writeln('RESUME "${r.label}"${r.label == focusLabel ? ' (chosen)' : ''}:');
      b.writeln(r.blindText);
      b.writeln();
    }
    if (transcript != null && transcript!.isNotEmpty) {
      b.writeln('VOICE TRANSCRIPT (their own words):\n$transcript\n');
    }
    if (answers.isNotEmpty) b.writeln('TYPED ANSWERS:\n${answers.join('\n')}');
    return b.toString();
  }

  String editsText() {
    if (edits.isEmpty) return '';
    final last = edits.length > 3 ? edits.sublist(edits.length - 3) : edits;
    return 'THE STUDENT EDITED PAST DRAFTS LIKE THIS (follow these preferences):\n' +
        last.map((e) => 'BEFORE: ${e['before']}\nAFTER: ${e['after']}').join('\n---\n');
  }
}
