import 'dart:math' as math;

import 'ai_service.dart';
import 'lint.dart';

/// Deterministic, grounded fallback. It only rearranges text that exists in
/// the student's materials and the employer data, so it cannot invent facts.
/// Output is always labelled "offline draft" in the app.
class OfflineAi implements AiService {
  @override
  String get name => 'offline';

  static const vocab = [
    'python', 'pytorch', 'llm', 'inference', 'latency', 'gpu', 'batching',
    'retrieval', 'rag', 'embeddings', 'evaluation', 'chunking', 'go', 'c++',
    'c', 'java', 'typescript', 'react', 'node', 'postgres', 'sql', 'spark',
    'airflow', 'pipelines', 'data modeling', 'distributed systems', 'storage',
    'replication', 'sre', 'slo', 'alerting', 'prometheus', 'grafana',
    'kubernetes', 'k3s', 'linux', 'on-call', 'runbooks', 'incident', 'embedded',
    'rtos', 'freertos', 'firmware', 'stm32', 'arm', 'telemetry', 'watchdog',
    'lora', 'radio', 'flight software', 'rf', 'matlab', 'analog', 'spice',
    'circuits', 'validation', 'test', 'automation', 'statistics', 'time series',
    'forecasting', 'backtesting', 'modeling', 'risk', 'credit risk', 'fraud',
    'dashboards', 'tableau', 'looker', 'reporting', 'logistics', 'operations',
    'experimentation', 'a/b testing', 'retention', 'payments', 'reconciliation',
    'backend', 'api', 'queues', 'docker', 'terraform', 'controls', 'perception',
    'unreal', 'gameplay', 'networking', 'observability', 'faiss', 'hugging face',
    'scikit-learn', 'lightgbm', 'pandas', 'excel', 'cad',
  ];

  static Set<String> skillsIn(String text) {
    final t = ' ${text.toLowerCase().replaceAll(RegExp(r'[,;()|/]'), ' ')} ';
    final out = <String>{};
    for (final v in vocab) {
      final re = RegExp('(?<![a-z0-9+])${RegExp.escape(v)}(?![a-z0-9+])');
      if (re.hasMatch(t)) out.add(v);
    }
    if (out.contains('prometheus') || out.contains('runbooks')) out.add('alerting');
    if (out.contains('slo') || out.contains('runbooks')) out.add('sre');
    if (t.contains('rag') || t.contains('retrieval')) out.add('retrieval');
    if (t.contains('time-series')) out.add('time series');
    if (t.contains('reconcil')) out.add('reconciliation');
    if (t.contains('payment')) out.add('payments');
    return out;
  }

  /// Items under PROJECTS / EXPERIENCE. Handles PDF text where bullets wrap
  /// onto several lines: continuation lines are joined back to their bullet,
  /// bullet characters are stripped, and each bullet is titled with the job or
  /// project header above it ("Boothwise: Built a retrieval pipeline ...").
  static List<String> itemLines(String text) {
    final raw = text.replaceAll('​', '').split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final bulletRe = RegExp(r'^[•\-\*–·▪●◦]\s*');
    final out = <String>[];
    var inSection = false;
    String? header; // current job / project title
    String? cur; // bullet being assembled
    void flush() {
      if (cur != null && cur!.length > 25) out.add(header != null && !cur!.contains(':') ? '$header: $cur' : cur!);
      cur = null;
    }

    for (final l in raw) {
      final up = l.toUpperCase();
      if (RegExp(r'^(PROJECTS|EXPERIENCE|WORK EXPERIENCE|RESEARCH|LEADERSHIP)\b').hasMatch(up) && l.length < 40) {
        flush();
        inSection = true;
        header = null;
        continue;
      }
      if (RegExp(r'^(SKILLS|TECHNICAL SKILLS|EDUCATION|COURSEWORK|AWARDS|INTERESTS|CERTIFICATIONS)\b').hasMatch(up) && l.length < 40) {
        flush();
        inSection = false;
        continue;
      }
      if (!inSection) continue;
      if (bulletRe.hasMatch(l)) {
        flush();
        cur = l.replaceFirst(bulletRe, '').trim();
      } else if (l.contains(' | ') || (RegExp(r'(19|20)\d{2}|\[year\]|\[date\]').hasMatch(l) && l.length < 90 && cur == null)) {
        // Job / project header line, e.g. "Boothwise | Co-Founder ... Sep 2025 - Present".
        flush();
        header = l.split('|').first.replaceAll(RegExp(r'\s+'), ' ').trim();
      } else if (cur != null) {
        cur = '$cur $l'; // wrapped continuation of the current bullet
      } else if (l.contains(':') && l.length > 25) {
        cur = l; // "Project: description" style lines (no bullet)
      } else if (l.length < 40) {
        continue; // location lines etc.
      } else {
        cur = l;
      }
    }
    flush();
    if (out.isEmpty) {
      out.addAll(text
          .split(RegExp(r'[\n.]'))
          .map((s) => s.trim())
          .where((s) => s.length > 30 && RegExp(r'\d').hasMatch(s)));
    }
    return out;
  }

  static String _itemName(String line) {
    final i = line.indexOf(':');
    if (i > 0 && i < 70) return line.substring(0, i).trim();
    return '';
  }

  static String _itemDetail(String line) {
    final i = line.indexOf(':');
    final body = i > 0 && i < 70 ? line.substring(i + 1).trim() : line;
    final parts = body
        .split(RegExp(r'(?<=[.;])\s+'))
        .map((s) => s.trim().replaceAll(RegExp(r'[.;]$'), ''))
        .where((s) => s.isNotEmpty)
        .toList();
    final withNum = parts.where((s) => RegExp(r'\d').hasMatch(s)).toList();
    return (withNum.isNotEmpty ? withNum.first : (parts.isNotEmpty ? parts.first : body));
  }

  /// "Name: detail", or just the detail when there is no name. Never repeats.
  static String _label(String line) {
    final n = _itemName(line), d = _itemDetail(line);
    if (n.isEmpty || d.toLowerCase().startsWith(n.toLowerCase())) return d;
    return '$n: $d';
  }

  /// Whole description of an item, cleaned, at most ~40 words.
  static String _itemWhat(String line) {
    final i = line.indexOf(':');
    var body = (i > 0 && i < 70 ? line.substring(i + 1) : line).trim();
    body = body.replaceAll(RegExp(r';\s*'), ', ').replaceAll(RegExp(r'[.]+$'), '');
    final words = body.split(RegExp(r'\s+'));
    if (words.length > 40) body = '${words.take(40).join(' ')}';
    return body;
  }

  /// A sentence from the voice transcript that talks about the same project.
  static String? _voiceDetailFor(StudentCtx s, String project) {
    final t = s.transcript;
    if (t == null || t.isEmpty) return null;
    Set<String> toks(String x) =>
        x.toLowerCase().split(RegExp(r'[^a-z0-9.]+')).where((w) => w.length > 3).toSet();
    final pt = toks(project);
    String? best;
    var bestScore = 0;
    for (final sent in sentences(t)) {
      if (wordCount(sent) > 28 || wordCount(sent) < 5) continue;
      final sc = toks(sent).intersection(pt).length + (RegExp(r'\d').hasMatch(sent) ? 1 : 0);
      if (sc > bestScore) {
        bestScore = sc;
        best = sent;
      }
    }
    return bestScore >= 2 ? best : null;
  }



  // ---------- fit ----------
  static ({double fit, Map<String, dynamic> role, Set<String> overlap})
      _bestRole(Set<String> skills, List<Map<String, dynamic>> roles) {
    var best = -1.0;
    Map<String, dynamic> bestRole = roles.first;
    var bestOverlap = <String>{};
    for (final r in roles) {
      final rs = ((r['skills'] as List?) ?? const []).cast<String>().toSet();
      if (rs.isEmpty) continue;
      final ov = rs.intersection(skills);
      final score = ov.length / rs.length;
      if (score > best) {
        best = score;
        bestRole = r;
        bestOverlap = ov;
      }
    }
    return (fit: math.max(0, best), role: bestRole, overlap: bestOverlap);
  }

  static String majorFlag(String major, BoothCtx b) {
    if (b.majors.any((m) => m.toLowerCase() == major.toLowerCase())) return 'yes';
    if (b.partialMajors.any((m) => m.toLowerCase() == major.toLowerCase())) return 'partial';
    return 'no';
  }

  @override
  Future<Map<String, dynamic>> boothFit(StudentCtx s, BoothCtx b) async => fitSync(s, b);

  Map<String, dynamic> fitSync(StudentCtx s, BoothCtx b) {
    double bestFit = -1;
    ResumeCtx bestR = s.resumes.first;
    Map<String, dynamic> bestRole = b.roles.first;
    Set<String> bestOv = {};
    final perResume = <String, double>{};
    for (final r in s.resumes) {
      final sk = skillsIn(r.blindText);
      final br = _bestRole(sk, b.roles);
      final mf = majorFlag(s.major, b);
      var f = 0.12 + 0.85 * math.min(1.0, br.fit * 1.5);
      f += mf == 'yes' ? 0.04 : (mf == 'partial' ? -0.04 : -0.15);
      f = f.clamp(0.05, 0.95);
      perResume[r.label] = f;
      if (f > bestFit + 1e-9) {
        bestFit = f;
        bestR = r;
        bestRole = br.role;
        bestOv = br.overlap;
      }
    }
    final roleTitle = bestRole['title'] as String;
    final reason = bestOv.isEmpty
        ? 'Little overlap with listed roles; closest is $roleTitle.'
        : '${_cap(bestOv.take(3).join(', '))} on resume match the $roleTitle role.';
    final others = perResume.keys.where((k) => k != bestR.label).toList();
    return {
      'fit': double.parse(bestFit.toStringAsFixed(2)),
      'fit_a': double.parse(bestFit.toStringAsFixed(2)),
      'fit_b': double.parse(bestFit.toStringAsFixed(2)),
      'resume_label': bestR.label,
      'reason': reason,
      'resume_reason': others.isEmpty
          ? 'Only resume uploaded.'
          : 'More overlap with $roleTitle than ${others.join(', ')}.',
      'matched_roles': bestOv.isEmpty ? <String>[] : [roleTitle],
      'source': 'offline',
    };
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ---------- resume / voice ----------
  @override
  Future<Map<String, dynamic>> parseResume(ResumeCtx r) async {
    final items = itemLines(r.blindText);
    return {
      'skills': skillsIn(r.blindText).toList(),
      'projects': [
        for (final l in items)
          {'name': _itemName(l), 'what': l, 'detail': _itemDetail(l), 'role': 'unknown'}
      ],
      'experience': <Map<String, dynamic>>[],
      'education': RegExp(r'(BS|MS|BA|MA|PhD|BTech|MBA)[^\n]*').firstMatch(r.blindText)?.group(0) ?? 'unknown',
      'source': 'offline',
    };
  }

  @override
  Future<Map<String, dynamic>> voiceProfile(String transcript, List<String> answers) async {
    final all = '$transcript ${answers.join(' ')}';
    final sents = sentences(all);
    final avg = sents.isEmpty
        ? 0
        : sents.map(wordCount).reduce((a, b) => a + b) / sents.length;
    final contractions = RegExp(r"\b\w+'(s|re|ve|ll|d|t|m)\b").allMatches(all).length;
    final casualMarkers = RegExp(r'\b(so|like|kind of|honestly|you know|stuff|okay|yeah)\b',
            caseSensitive: false)
        .allMatches(all)
        .length;
    final formality = contractions == 0 && casualMarkers < 2
        ? 'formal'
        : (casualMarkers >= 4 ? 'casual' : 'neutral');
    final firstNum = all.indexOf(RegExp(r'\d'));
    final explains = all.toLowerCase().contains(' like a ')
        ? 'analogy-first'
        : (firstNum >= 0 && firstNum < 80 ? 'numbers-first' : 'story-first');
    final details = sents.where((s) => RegExp(r'\d|percent|hertz|weeks?|times').hasMatch(s)).take(4).toList();
    return {
      'sentence_length': avg < 9 ? 'short' : (avg < 17 ? 'medium' : 'long'),
      'rhythm': explains,
      'contractions': contractions > 0,
      'formality': formality,
      'phrases': sents.take(3).map((s) => s.split(' ').take(6).join(' ')).toList(),
      'self_description': 'unknown',
      'explains_technical': explains,
      'signature_details': details.isEmpty ? sents.take(2).toList() : details,
      'source': 'offline',
    };
  }

  // ---------- pitch ----------
  static String _formality(StudentCtx s) =>
      (s.voiceProfile?['formality'] as String?) ?? 'neutral';
  static bool _contractions(StudentCtx s) =>
      (s.voiceProfile?['contractions'] as bool?) ?? true;

  static String questionFor(Map<String, dynamic> role, bool contractions) {
    final d = '${role['title']} ${role['desc']}'.toLowerCase();
    final t = role['title'];
    String q;
    if (d.contains('on-call')) {
      q = 'For the $t role, how long before a new hire joins the on-call rotation, and what do they own first?';
    } else if (d.contains('latency') || d.contains('batching')) {
      q = 'On the $t team, is the work mostly tuning latency on existing models, or changing how requests get batched and scheduled?';
    } else if (d.contains('evaluation') || d.contains('evals')) {
      q = 'For $t, do your evaluation sets come from customer questions or do you build them in-house?';
    } else if (d.contains('forecast')) {
      q = 'For the $t role, which decision does the forecast feed into, and who checks it after the fact?';
    } else if (d.contains('backtest') || d.contains('validate')) {
      q = 'For $t, how do you decide a signal has failed out of sample, and how long do you watch it before deciding?';
    } else if (d.contains('telemetry') || d.contains('watchdog')) {
      q = 'For the $t role, how do you test reset and recovery behaviour before hardware goes into the field?';
    } else if (d.contains('dashboard') || d.contains('analysis')) {
      q = 'For $t, who reads the dashboards each week, and what decision do they make from them?';
    } else if (d.contains('rotation')) {
      q = 'In the $t, who decides the rotation order, and can someone ask to repeat a team?';
    } else {
      final parts = (role['desc'] as String).split(RegExp(r'[.;]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      final clause = parts.firstWhere((x) => x.split(' ').length >= 4 && !x.contains(','), orElse: () => '');
      q = clause.isEmpty
          ? 'For the $t role, what does a new hire ship in the first month, and who reviews it?'
          : 'For the $t role, which part of "${clause[0].toLowerCase()}${clause.substring(1)}" would a new hire own in the first three months?';
    }
    if (!contractions) q = q.replaceAll("what's", 'what is');
    return q;
  }

  @override
  Future<Map<String, dynamic>> pitch(StudentCtx s, BoothCtx b,
      {String variant = 'default', String? resumeLabel, String? excludeProject}) async {
    final r = s.resumeByLabel(resumeLabel) ?? s.defaultResume;
    final items = itemLines(r.blindText);
    final scored = <(String, double, Map<String, dynamic>)>[];
    for (final l in items) {
      final br = _bestRole(skillsIn(l), b.roles);
      scored.add((l, br.fit, br.role));
    }
    scored.sort((a, c) => c.$2.compareTo(a.$2));
    var pick = scored.isNotEmpty ? scored.first : null;
    if (variant == 'different_project' && scored.length > 1) {
      pick = scored.firstWhere((x) => _itemName(x.$1) != excludeProject,
          orElse: () => scored[1]);
    }
    final formal = _formality(s) == 'formal';
    final casual = _formality(s) == 'casual';
    final con = _contractions(s);
    final degree = s.degree.isEmpty ? '' : '${s.degree} ';
    final intro = formal
        ? 'Good to meet you. My name is ${s.firstName}, and I am completing my $degree in ${s.major}.'
            .replaceAll('$degree in', '${degree.trim()} in')
        : casual
            ? "Hey, I'm ${s.firstName}, doing my ${degree.trim()} in ${s.major}."
            : "I'm ${s.firstName}, ${s.major}.";
    String body;
    String connect;
    Map<String, dynamic> role = pick?.$3 ?? b.roles.first;
    if (pick == null) {
      body = con ? "I don't have a project on my resume that maps cleanly here yet." : 'I do not yet have a project on my resume that maps cleanly here.';
    } else {
      final name = _itemName(pick.$1);
      final what = _itemWhat(pick.$1);
      // The student's own words about this project, if the Voice Profile has them.
      final own = _voiceDetailFor(s, '$name $what');
      final thing = name.isEmpty ? what : '$name: $what';
      body = formal
          ? 'The most relevant work is ${name.isEmpty ? 'this' : name}: $what.'
          : (casual ? 'So the thing I worked on most: $thing.' : '$thing.');
      if (own != null) body = '$body $own';
      // Still short? Add the next most relevant item, briefly.
      if (wordCount(body) < 30 && scored.length > 1) {
        final second = scored.firstWhere((x) => x.$1 != pick!.$1, orElse: () => scored.last);
        if (second.$1 != pick.$1) {
          body = '$body ${formal ? 'In addition, ' : 'Also, '}${_label(second.$1)}.';
        }
      }
    }
    connect = formal
        ? 'That work is closest to your ${role['title']} position.'
        : (con
            ? "That's closest to your ${role['title']} role."
            : 'That is closest to your ${role['title']} role.');
    var text = '$intro $body $connect';
    if (variant == 'shorter') text = '$body $connect';
    final question = questionFor(role, con);
    final sources = {
      for (final x in s.resumes) 'Resume "${x.label}"': x.blindText,
      if (s.transcript != null) 'Voice Profile': s.transcript!,
      'Employer data': b.asText,
    };
    return {
      'pitch': text.replaceAll(RegExp(r'\.\.+'), '.'),
      'question': question,
      'talking_points': [
        if (pick != null) _itemDetail(pick.$1),
        'Ties to ${role['title']}',
      ].take(2).toList(),
      'trace': traceSentences(text, sources),
      'project': pick == null ? 'unknown' : _itemName(pick.$1),
      'resume_label': r.label,
      'variant': variant,
      'source': 'offline',
      'facts': {
        'projects': [
          if (pick != null) {'name': _itemName(pick.$1), 'detail': _itemDetail(pick.$1), 'source': 'Resume "${r.label}"'}
        ],
        'connection': {'role': role['title'], 'why': 'skill overlap'},
        'question': question,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> dropNote(StudentCtx s, BoothCtx b, ResumeCtx r) async {
    final items = itemLines(r.blindText);
    String line1 = 'Resume attached.';
    Map<String, dynamic> role = b.roles.first;
    var best = -1.0;
    for (final l in items) {
      final br = _bestRole(skillsIn(l), b.roles);
      if (br.fit > best) {
        best = br.fit;
        line1 = '${_label(l)}.';
        role = br.role;
      }
    }
    return {'note': '$line1\nFor the ${role['title']} role.', 'source': 'offline'};
  }

  @override
  Future<Map<String, dynamic>> recruiterSummary(StudentCtx s, BoothCtx b, ResumeCtx r) async =>
      summarySync(b, r);

  Map<String, dynamic> summarySync(BoothCtx b, ResumeCtx r) {
    final items = itemLines(r.blindText);
    final sk = skillsIn(r.blindText);
    final br = _bestRole(sk, b.roles);
    final ranked = [...items]..sort((a, c) =>
        _bestRole(skillsIn(c), b.roles).fit.compareTo(_bestRole(skillsIn(a), b.roles).fit));
    return {
      'headline': ranked.isEmpty ? 'Resume text available' : _label(ranked.first),
      'highlights': [for (final l in ranked.skip(1).take(3)) _label(l)],
      'best_role': br.fit > 0 ? br.role['title'] : 'unknown',
      'fit_reason': br.overlap.isEmpty
          ? 'Little overlap with listed roles.'
          : 'Overlap: ${br.overlap.take(4).join(', ')}.',
      'source': 'offline',
    };
  }

  @override
  Future<Map<String, dynamic>> followUpEmail(StudentCtx s, BoothCtx b,
      {required String note, required String recruiterName, ResumeCtx? resume}) async {
    final formal = _formality(s) == 'formal';
    final r = resume ?? s.defaultResume;
    final items = itemLines(r.blindText);
    final fact = items.isEmpty ? '' : '${_label(items.first)}.';
    final first = recruiterName.split(' ').first;
    final n = note.trim().replaceAll(RegExp(r'\s+'), ' ');
    final body = formal
        ? 'Dear $first,\n\nThank you for speaking with me at the career fair today. You mentioned: "$n". The most relevant work on my resume is $fact\n\nI have attached my resume. Could you tell me the best way to apply for the role we discussed?\n\nBest regards,\n${s.firstName}'
        : 'Hi $first,\n\nThanks for the chat at the fair today. You mentioned: "$n". The closest thing on my resume is $fact\n\nResume attached. What is the best way to apply for the role we talked about?\n\n${s.firstName}';
    return {
      'subject': 'Following up from the career fair: ${b.name}',
      'body': body,
      'source': 'offline',
    };
  }
}
