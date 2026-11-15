import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../ai/ai_service.dart';
import '../ai/cached_ai_service.dart';
import '../ai/lint.dart';
import '../ai/offline_ai.dart';
import '../ai/transcribe.dart';
import '../config.dart';
import '../db/db.dart';
import '../fairness/fairness_engine.dart';
import '../game/game.dart';
import '../util/codes.dart';
import 'hub.dart';
import 'jobs.dart';

class ApiError implements Exception {
  final int status;
  final String message;
  final Map<String, Object?> extra;
  ApiError(this.status, this.message, [this.extra = const {}]);
  @override
  String toString() => message;
}

const workAuthLabels = {
  'citizen': 'US citizen',
  'permanent_resident': 'Permanent resident',
  'f1_cpt_opt': 'F-1, needs CPT/OPT',
  'h1b': 'Will need H-1B sponsorship',
};

/// QueueCue domain service. Everything the routes need lives here so the
/// rules are testable without HTTP.
class QQ {
  final Db db;
  final Config cfg;
  final Codes codes;
  final AiRouter ai;
  final Hub hub;
  final Transcriber whisper;
  late final Jobs jobs;
  late final Game game;
  int Function() clock;
  final Random rnd = Random();
  Timer? simTimer;

  QQ({
    required this.db,
    required this.cfg,
    required this.codes,
    required this.ai,
    required this.hub,
    required this.whisper,
    int Function()? clock,
  }) : clock = clock ?? nowMs {
    jobs = Jobs(this);
    game = Game(this);
  }

  // ---------------------------------------------------------------- basics
  Row fair() => db.one('SELECT * FROM fairs LIMIT 1') ?? (throw ApiError(500, 'No fair seeded. Run reset.'));
  String get fairId => fair()['id'] as String;
  bool get fairOpen => fair()['status'] == 'open';
  bool get demoMode => db.meta('demo_mode') != '0';
  bool get aiLive => db.meta('ai_live') == '1';
  bool get simulating => simTimer != null;

  FairnessSettings settings() {
    final f = fair();
    return FairnessSettings(
      wFit: (f['w_fit'] as num).toDouble(),
      wEffort: (f['w_effort'] as num).toDouble(),
      capMin: f['effort_cap_min'] as int,
      seed: f['seed'] as String,
    );
  }

  FairnessEngine get engine => FairnessEngine(settings());

  List<Row> booths() => db.all('SELECT * FROM booths ORDER BY number');
  Row booth(String id) =>
      db.one('SELECT * FROM booths WHERE id=?', [id]) ?? (throw ApiError(404, 'Booth not found'));
  Row student(String id) =>
      db.one('SELECT * FROM students WHERE id=?', [id]) ?? (throw ApiError(404, 'Student not found'));
  Row? studentByToken(String? token) =>
      token == null ? null : db.one('SELECT * FROM students WHERE token=?', [token]);

  Row boothByKey(String boothId, String? key) {
    final b = booth(boothId);
    if (key == null || key != b['booth_key']) {
      throw ApiError(403, 'This link needs the booth key. Ask the organizer for your booth link.');
    }
    return b;
  }

  void requireOrganizer(String? key) {
    if (key != cfg.organizerKey) throw ApiError(403, 'Organizer key required.');
  }

  BoothCtx boothCtx(Row b) => BoothCtx(
        id: b['id'] as String,
        name: b['name'] as String,
        category: (b['category'] ?? '') as String,
        about: (b['about'] ?? '') as String,
        roles: (jd(b['roles_json']) as List).cast<Map<String, dynamic>>(),
        sponsors: b['sponsors'] as String,
        majors: (jd(b['majors_json']) as List).cast<String>(),
        partialMajors: (jd(b['partial_majors_json']) as List).cast<String>(),
        citizenshipRequired: b['citizenship_required'] == 1,
        recruiterName: b['recruiter_name'] as String?,
      );

  List<Row> resumes(String sid) =>
      db.all('SELECT * FROM resumes WHERE student_id=? ORDER BY created_at, id', [sid]);

  Row? resume(String? id) => id == null ? null : db.one('SELECT * FROM resumes WHERE id=?', [id]);

  StudentCtx studentCtx(String sid) {
    final s = student(sid);
    final vp = db.one('SELECT * FROM voice_profiles WHERE student_id=?', [sid]);
    final rs = resumes(sid);
    if (rs.isEmpty) throw ApiError(400, 'Upload at least one resume first.');
    return StudentCtx(
      id: sid,
      persona: s['persona'] as String?,
      firstName: (s['name'] as String).split(' ').first,
      major: s['major'] as String,
      degree: (s['degree'] ?? '') as String,
      workAuth: s['work_auth'] as String,
      resumes: [
        for (final r in rs)
          ResumeCtx(
            id: r['id'] as String,
            label: r['label'] as String,
            blindText: r['blind_text'] as String,
            isDefault: r['is_default'] == 1,
            parsed: (jd(r['parsed_json']) as Map?)?.cast<String, dynamic>(),
          )
      ],
      voiceProfile: (jd(vp?['profile_json']) as Map?)?.cast<String, dynamic>(),
      transcript: vp?['transcript'] as String?,
      answers: ((jd(vp?['answers_json']) as List?) ?? const []).cast<String>(),
      edits: ((jd(vp?['edits_json']) as List?) ?? const []).cast<Map<String, dynamic>>(),
    );
  }

  void changed(Iterable<String> topics) => hub.changed(topics);

  // ---------------------------------------------------------- eligibility
  Map<String, Object?> eligibility(Row s, Row b) {
    final auth = s['work_auth'] as String;
    final needsSponsor = auth == 'f1_cpt_opt' || auth == 'h1b';
    final citizenBlock = b['citizenship_required'] == 1 && auth != 'citizen';
    final majors = (jd(b['majors_json']) as List).cast<String>();
    final partial = (jd(b['partial_majors_json']) as List).cast<String>();
    final m = (s['major'] as String).toLowerCase();
    final majorFlag = majors.any((x) => x.toLowerCase() == m)
        ? 'yes'
        : (partial.any((x) => x.toLowerCase() == m) ? 'partial' : 'no');
    final sponsors = b['sponsors'] as String;
    final sponsorBlock = needsSponsor && sponsors == 'no';
    final reasons = <String>[
      if (citizenBlock) 'US citizens only',
      if (sponsorBlock) 'Does not sponsor visas',
      if (majorFlag == 'no') 'Does not list your major',
    ];
    return {
      'sponsors': sponsors,
      'needs_sponsor': needsSponsor,
      'major_flag': majorFlag,
      'citizenship_required': b['citizenship_required'] == 1,
      'citizen_block': citizenBlock,
      'sponsor_block': sponsorBlock,
      'eligible': reasons.isEmpty,
      'block_reasons': reasons,
    };
  }

  // ------------------------------------------------------------------ plan
  Future<void> computeFit(String sid, String boothId) async {
    final s = student(sid);
    final b = booth(boothId);
    final ctx = studentCtx(sid);
    final r = s['is_sim'] == 1 ? offline.fitSync(ctx, boothCtx(b)) : await ai.boothFit(ctx, boothCtx(b));
    final res = ctx.resumeByLabel(r['resume_label'] as String?) ?? ctx.defaultResume;
    final el = eligibility(s, b);
    db.upsert('fits', {
      'student_id': sid,
      'booth_id': boothId,
      'fit': (r['fit'] as num).toDouble(),
      'fit_a': (r['fit_a'] as num?)?.toDouble(),
      'fit_b': (r['fit_b'] as num?)?.toDouble(),
      'resume_id': res.id,
      'reason': r['reason'],
      'resume_reason': r['resume_reason'],
      'sponsor_flag': el['sponsors'],
      'major_flag': el['major_flag'],
      'citizenship_block': el['citizen_block'] == true ? 1 : 0,
      'eligible': el['eligible'] == true ? 1 : 0,
      'source': r['source'],
      'matched_roles_json': je(r['matched_roles'] ?? []),
      'updated_at': clock(),
    }, ['student_id', 'booth_id']);
  }

  Row? fit(String sid, String boothId) =>
      db.one('SELECT * FROM fits WHERE student_id=? AND booth_id=?', [sid, boothId]);

  /// Ranked plan. Never hides a booth: ineligible booths are listed below the
  /// eligible ones with the reason.
  Map<String, Object?> plan(String sid) {
    final s = student(sid);
    final out = <Map<String, Object?>>[];
    for (final b in booths()) {
      final f = fit(sid, b['id'] as String);
      final el = eligibility(s, b);
      final res = resume(f?['resume_id'] as String?);
      final line = lineState(b['id'] as String, sid);
      final fitV = (f?['fit'] as num?)?.toDouble();
      out.add({
        'booth': publicBooth(b),
        'fit': fitV,
        'fit_pct': fitV == null ? null : (fitV * 100).round(),
        'fit_label': fitV == null ? 'pending' : (fitV >= 0.7 ? 'high fit' : (fitV >= 0.5 ? 'medium fit' : 'low fit')),
        'reason': f?['reason'],
        'resume_id': res?['id'],
        'resume_label': res?['label'],
        'resume_reason': f?['resume_reason'],
        'source': f?['source'],
        ...el,
        'line': line,
        'off_beaten': fitV != null && fitV >= 0.8 && el['eligible'] == true &&
            (line['estimate'] as Map)['high_min'] as int < 10 && b['status'] == 'open',
      });
    }
    out.sort((a, c) {
      final ea = a['eligible'] == true ? 0 : 1, ec = c['eligible'] == true ? 0 : 1;
      if (ea != ec) return ea.compareTo(ec);
      return ((c['fit'] as double?) ?? -1).compareTo((a['fit'] as double?) ?? -1);
    });
    for (var i = 0; i < out.length; i++) {
      out[i]['rank'] = i + 1;
    }
    return {
      'items': out,
      'pending': out.any((x) => x['fit'] == null),
      'quests': game.questsFor(sid),
    };
  }

  Map<String, Object?> publicBooth(Row b) => {
        'id': b['id'],
        'number': b['number'],
        'name': b['name'],
        'category': b['category'],
        'tagline': b['tagline'],
        'about': b['about'],
        'roles': jd(b['roles_json']),
        'sponsors': b['sponsors'],
        'majors': jd(b['majors_json']),
        'citizenship_required': b['citizenship_required'] == 1,
        'x': b['x'],
        'y': b['y'],
        'status': b['status'],
        'recruiter_name': b['recruiter_name'],
      };

  // ----------------------------------------------------------------- queue
  List<Row> waiting(String boothId) => db.all(
      "SELECT * FROM queue_entries WHERE booth_id=? AND status='waiting' ORDER BY joined_at, id",
      [boothId]);

  double avgServiceMin(String boothId) {
    final b = booth(boothId);
    final xs = db
        .all('SELECT service_sec FROM exchanges WHERE booth_id=? AND service_sec IS NOT NULL '
            'ORDER BY created_at DESC LIMIT 8', [boothId])
        .map((r) => (r['service_sec'] as num).toDouble())
        .toList();
    return rollingServiceMin(xs, (b['default_service_min'] as num).toDouble());
  }

  Map<String, Object?> lineState(String boothId, [String? sid]) {
    final w = waiting(boothId);
    final avg = avgServiceMin(boothId);
    final idx = sid == null ? -1 : w.indexWhere((e) => e['student_id'] == sid);
    final ahead = idx >= 0 ? idx : w.length;
    final est = WaitEstimate.of(ahead, avg);
    return {
      'count': w.length,
      'in_line': idx >= 0,
      'position': idx >= 0 ? idx + 1 : null,
      'ahead': ahead,
      'estimate': est.toJson(),
      'joined_at': idx >= 0 ? w[idx]['joined_at'] : null,
      'waited_min': idx >= 0 ? ((clock() - (w[idx]['joined_at'] as int)) / 60000).floor() : null,
    };
  }

  void checkIn(String sid) {
    final s = student(sid);
    if (s['checked_in_at'] != null) return;
    db.exec('UPDATE students SET checked_in_at=? WHERE id=?', [clock(), sid]);
    game.onCheckIn(sid);
  }

  /// Joining a line or dropping a resume is a plain button (no booth QR).
  /// Neither ever counts as a conversation: only the recruiter can confirm one.
  void _requireBoothAccess(String boothId, String? token) {}

  Map<String, Object?> join(String sid, String boothId, {String? token, String? resumeId}) {
    if (!fairOpen) throw ApiError(409, 'The fair is closed.');
    final b = booth(boothId);
    if (b['status'] != 'open') throw ApiError(409, '${b['name']} has closed its line.');
    _requireBoothAccess(boothId, token);
    if (db.one('SELECT 1 FROM exchanges WHERE booth_id=? AND student_id=?', [boothId, sid]) != null) {
      throw ApiError(409, 'You already met ${b['name']}.');
    }
    final current = db.one(
        "SELECT q.*, b.name AS booth_name FROM queue_entries q JOIN booths b ON b.id=q.booth_id "
        "WHERE q.student_id=? AND q.status='waiting'", [sid]);
    if (current != null) {
      if (current['booth_id'] == boothId) return lineState(boothId, sid);
      throw ApiError(409, 'You are in line at ${current['booth_name']}. Leave that line first.',
          {'current_booth': current['booth_id']});
    }
    checkIn(sid);
    final est = WaitEstimate.of(waiting(boothId).length, avgServiceMin(boothId));
    db.insert('queue_entries', {
      'booth_id': boothId,
      'student_id': sid,
      'resume_id': resumeId ?? fit(sid, boothId)?['resume_id'],
      'joined_at': clock(),
      'status': 'waiting',
      'est_wait_at_join': est.highMin.toDouble(),
      'via_qr': codes.verifyBoothJoin(boothId, token) ? 1 : 0,
    });
    changed(['booth:$boothId', 'student:$sid', 'organizer']);
    return lineState(boothId, sid);
  }

  void leave(String sid, String boothId) {
    db.exec(
        "UPDATE queue_entries SET status='left', left_at=? WHERE student_id=? AND booth_id=? AND status='waiting'",
        [clock(), sid, boothId]);
    changed(['booth:$boothId', 'student:$sid', 'organizer']);
  }

  // ----------------------------------------------------------------- drops
  Map<String, Object?> drop(String sid, String boothId,
      {required String resumeId, String? note, String? token}) {
    if (!fairOpen) throw ApiError(409, 'The fair is closed.');
    final b = booth(boothId);
    _requireBoothAccess(boothId, token);
    final r = resume(resumeId);
    if (r == null || r['student_id'] != sid) throw ApiError(400, 'Pick one of your resumes.');
    checkIn(sid);
    final cleanNote = (note ?? '').trim();
    if (cleanNote.split('\n').length > 2 || cleanNote.length > 280) {
      throw ApiError(400, 'Keep the note to 2 short lines.');
    }
    final est = WaitEstimate.of(waiting(boothId).length, avgServiceMin(boothId));
    final existing =
        db.one("SELECT id FROM drops WHERE booth_id=? AND student_id=? AND kind='drop'", [boothId, sid]);
    if (existing != null) {
      db.exec('UPDATE drops SET resume_id=?, note=?, created_at=? WHERE id=?',
          [resumeId, cleanNote, clock(), existing['id']]);
    } else {
      db.insert('drops', {
        'booth_id': boothId,
        'student_id': sid,
        'resume_id': resumeId,
        'note': cleanNote,
        'kind': 'drop',
        'est_wait_min': (est.lowMin + est.highMin) / 2,
        'created_at': clock(),
      });
    }
    game.onDrop(sid, boothId, resumeId);
    jobs.ensureSummary(boothId, sid, resumeId);
    changed(['booth:$boothId', 'student:$sid', 'organizer']);
    return {
      'message': 'Dropped at Booth ${b['number']}. The recruiter can see it now.',
      'updated': existing != null,
    };
  }

  // ------------------------------------------------------ card exchange
  /// Presence verification. Only callable with the booth key (recruiter's
  /// device) or the organizer key (staff, accessibility exception).
  Map<String, Object?> confirm(
    String boothId, {
    String? code,
    String? studentId,
    int? number,
    bool fromRequest = false,
    bool group = false,
    String? pile,
    String? memory,
    String confirmedBy = 'recruiter',
  }) {
    final b = booth(boothId);
    final now = clock();
    String sid;
    String method;
    if (code != null && code.isNotEmpty) {
      final v = codes.verifyStudentCode(code, now);
      if (v == null) {
        throw ApiError(400, 'That QR code has expired or is not a QueueCue student code. Ask the student to show the live code.');
      }
      sid = v;
      method = 'scan';
    } else if (number != null) {
      final s = db.one('SELECT id FROM students WHERE number=?', [number]);
      if (s == null) throw ApiError(404, 'No student has number $number.');
      sid = s['id'] as String;
      method = 'number';
    } else if (studentId != null && fromRequest) {
      sid = studentId;
      method = 'card';
    } else if (studentId != null) {
      sid = studentId;
      method = confirmedBy == 'staff' ? 'staff' : 'met';
      if (method == 'met') {
        final w = waiting(boothId);
        if (w.isEmpty || w.first['student_id'] != sid) {
          throw ApiError(409, '"Met" works for the person at the top of the line. Use "Enter student number" instead.');
        }
      }
    } else {
      throw ApiError(400, 'Enter the student number, accept their card, or tap Met.');
    }
    final s = student(sid);
    if (s['checked_in_at'] == null) {
      throw ApiError(409, 'Only checked-in students can be confirmed.');
    }
    if (method == 'staff' && s['accommodation'] != 1) {
      throw ApiError(409, 'Staff confirmation is for students with a logged accommodation.');
    }
    final prev = db.one('SELECT created_at FROM exchanges WHERE booth_id=? AND student_id=?', [boothId, sid]);
    if (prev != null) {
      throw ApiError(409, '${s['name']} was already confirmed at this booth.', {'already': true});
    }
    final last = b['last_confirm_at'] as int?;
    if (method != 'staff' && !group && last != null && now - last < 20000) {
      throw ApiError(409, 'Group chat? You confirmed someone ${((now - last) / 1000).round()} s ago.',
          {'needs_group': true, 'student_name': s['name']});
    }
    final q = db.one(
        "SELECT * FROM queue_entries WHERE booth_id=? AND student_id=? AND status='waiting'", [boothId, sid]);
    final waitedMin = q == null ? 0.0 : (now - (q['joined_at'] as int)) / 60000.0;
    final serviceSec = last != null && now - last < 20 * 60 * 1000 ? (now - last) / 1000.0 : null;
    final resumeId = q?['resume_id'] ?? fit(sid, boothId)?['resume_id'] ??
        db.scalar('SELECT id FROM resumes WHERE student_id=? ORDER BY is_default DESC LIMIT 1', [sid]);
    late int exId;
    db.tx(() {
      if (q != null) {
        db.exec("UPDATE queue_entries SET status='served', left_at=? WHERE id=?", [now, q['id']]);
      }
      exId = db.insert('exchanges', {
        'booth_id': boothId,
        'student_id': sid,
        'method': method,
        'confirmed_by': confirmedBy,
        'service_sec': serviceSec,
        'waited_min': waitedMin,
        'resume_id': resumeId,
        'created_at': now,
      });
      if (method != 'staff') {
        db.exec('UPDATE booths SET last_confirm_at=? WHERE id=?', [now, boothId]);
      }
      db.upsert('rolodex', {
        'student_id': sid,
        'booth_id': boothId,
        'exchange_id': exId,
        'created_at': now,
      }, ['student_id', 'booth_id']);
      if (pile != null || memory != null) {
        mark(boothId, sid, pile: pile, memory: memory);
      }
    });
    game.onExchange(sid, boothId, exId);
    if (resumeId != null) jobs.ensureSummary(boothId, sid, resumeId as String);
    changed(['booth:$boothId', 'student:$sid', 'organizer', 'fair']);
    return {
      'exchange_id': exId,
      'student': studentCard(s),
      'method': method,
      'waited_min': double.parse(waitedMin.toStringAsFixed(1)),
      'message': 'Cards swapped with ${s['name']}.',
    };
  }

  Map<String, Object?> studentCard(Row s) => {
        'id': s['id'],
        'number': s['number'],
        'interests': s['interests'],
        'bio': s['bio'],
        'name': s['name'],
        'avatar': s['avatar'],
        'major': s['major'],
        'degree': s['degree'],
        'email': s['email'],
        'linkedin': s['linkedin'],
      };

  Map<String, Object?> recruiterCard(Row b) => {
        'number': b['recruiter_number'],
        'booth_id': b['id'],
        'company': b['name'],
        'title': b['recruiter_title'],
        'name': b['recruiter_name'],
        'email': (b['contact_email'] as String?)?.isNotEmpty == true ? b['contact_email'] : b['recruiter_email'],
        'booth_number': b['number'],
      };

  void mark(String boothId, String sid,
      {double? stars, String? privateNote, String? pile, String? memory, double? manualRank,
      List<String>? tags, bool clearPile = false, bool clearStars = false}) {
    final cur = db.one('SELECT * FROM recruiter_marks WHERE booth_id=? AND student_id=?', [boothId, sid]);
    if (pile != null) {
      final piles = (jd(booth(boothId)['piles_json']) as List).cast<String>();
      if (!piles.contains(pile)) throw ApiError(400, 'Unknown pile "$pile".');
    }
    if (stars != null && (stars < 1 || stars > 5)) throw ApiError(400, 'Stars are 1 to 5.');
    db.upsert('recruiter_marks', {
      'booth_id': boothId,
      'student_id': sid,
      'stars': clearStars ? null : (stars ?? cur?['stars']),
      'private_note': privateNote ?? cur?['private_note'],
      'pile': clearPile ? null : (pile ?? cur?['pile']),
      'memory_note': memory ?? cur?['memory_note'],
      'manual_rank': manualRank ?? cur?['manual_rank'],
      'tags_json': tags != null ? je(tags) : cur?['tags_json'],
      'updated_at': clock(),
    }, ['booth_id', 'student_id']);
    changed(['booth:$boothId']);
  }

  // ------------------------------------------------------------ shortlist
  double waitedAt(String boothId, String sid) {
    final now = clock();
    var total = 0.0;
    for (final q in db.all('SELECT joined_at, left_at, status FROM queue_entries WHERE booth_id=? AND student_id=?',
        [boothId, sid])) {
      final end = (q['left_at'] as int?) ?? now;
      total += (end - (q['joined_at'] as int)) / 60000.0;
    }
    return total;
  }

  List<String> shortlistStudentIds(String boothId) => db
      .all('SELECT student_id FROM exchanges WHERE booth_id=? UNION SELECT student_id FROM drops WHERE booth_id=?',
          [boothId, boothId])
      .map((r) => r['student_id'] as String)
      .toList();

  Candidate candidate(String boothId, String sid) {
    final s = student(sid);
    final f = fit(sid, boothId);
    final kinds = db
        .all('SELECT kind FROM drops WHERE booth_id=? AND student_id=?', [boothId, sid])
        .map((r) => r['kind'] as String)
        .toSet();
    final met = db.one('SELECT 1 FROM exchanges WHERE booth_id=? AND student_id=?', [boothId, sid]) != null;
    return Candidate(
      studentId: sid,
      fit: (f?['fit'] as num?)?.toDouble() ?? 0,
      waitedMin: waitedAt(boothId, sid),
      verified: met,
      lineCredit: kinds.contains('line_credit'),
      sent: kinds.contains('drop') || kinds.contains('fairplay'),
      name: s['name'] as String,
      arrivalMs: (s['checked_in_at'] as int?) ?? 0,
      points: game.totalPoints(sid),
      gradYear: (s['grad_year'] as int?) ?? 0,
    );
  }

  List<Ranked> rankBooth(String boothId) =>
      engine.rank(boothId, [for (final sid in shortlistStudentIds(boothId)) candidate(boothId, sid)]);

  Map<String, Object?> recruiterView(String boothId, {bool includeIdentity = true}) {
    final b = booth(boothId);
    final piles = (jd(b['piles_json']) as List).cast<String>();
    final ranked = rankBooth(boothId);
    final cards = <Map<String, Object?>>[];
    for (final r in ranked) {
      final sid = r.c.studentId;
      final s = student(sid);
      final f = fit(sid, boothId);
      final ex = db.one('SELECT * FROM exchanges WHERE booth_id=? AND student_id=?', [boothId, sid]);
      final ds = db.all('SELECT * FROM drops WHERE booth_id=? AND student_id=? ORDER BY created_at', [boothId, sid]);
      final mk = db.one('SELECT * FROM recruiter_marks WHERE booth_id=? AND student_id=?', [boothId, sid]);
      final firstQ = db.scalar('SELECT MIN(joined_at) FROM queue_entries WHERE booth_id=? AND student_id=?', [boothId, sid]) as int?;
      final times = [
        if (firstQ != null) firstQ,
        if (ex != null) ex['created_at'] as int,
        for (final d in ds) d['created_at'] as int,
      ];
      final resumeId = (ex?['resume_id'] ?? (ds.isNotEmpty ? ds.last['resume_id'] : null) ?? f?['resume_id']) as String?;
      final res = resume(resumeId);
      final sum = resumeId == null
          ? null
          : db.one('SELECT json FROM summaries WHERE booth_id=? AND student_id=? AND resume_id=?', [boothId, sid, resumeId]);
      final lc = ds.where((d) => d['kind'] == 'line_credit').toList();
      cards.add({
        ...r.toJson(),
        'student': studentCard(s),
        'kinds': [
          if (ex != null) 'met',
          for (final d in ds) d['kind'],
        ],
        'met_at': ex?['created_at'],
        'met_method': ex?['method'],
        'arrival_at': times.isEmpty ? null : times.reduce(min),
        'reason': f?['reason'],
        'fit_pct': ((r.c.fit) * 100).round(),
        'resume_id': resumeId,
        'resume_label': res?['label'],
        'has_pdf': res?['pdf_path'] != null,
        'note': ds.where((d) => (d['note'] as String?)?.isNotEmpty == true).map((d) => d['note']).lastOrNull,
        'line_credit_label': lc.isEmpty
            ? null
            : 'Waited ${(lc.first['waited_min'] as num).round()} min, did not reach you',
        'summary': jd(sum?['json']),
        'pile': mk?['pile'],
        'memory_note': mk?['memory_note'],
        'tags': jd(mk?['tags_json']) ?? const [],
        'stars': mk?['stars'],
        'private_note': mk?['private_note'],
        'manual_rank': mk?['manual_rank'],
      });
    }
    final w = waiting(boothId);
    final line = [
      for (final e in w)
        {
          'student': studentCard(student(e['student_id'] as String)),
          'joined_at': e['joined_at'],
          'waited_min': ((clock() - (e['joined_at'] as int)) / 60000).floor(),
          'fit_pct': (((fit(e['student_id'] as String, boothId)?['fit'] as num?) ?? 0) * 100).round(),
        }
    ];
    final st = settings();
    return {
      'booth': {...publicBooth(b), 'piles': piles, 'recruiter_email': b['recruiter_email']},
      'fair': {'status': fair()['status'], 'name': fair()['name'], 'seed_hash': fair()['seed_hash']},
      'settings': {'w_fit': st.wFit, 'w_effort': st.wEffort, 'cap_min': st.capMin, 'formula': st.formula},
      'line': line,
      'line_estimate': WaitEstimate.of(w.length, avgServiceMin(boothId)).toJson(),
      'avg_service_min': double.parse(avgServiceMin(boothId).toStringAsFixed(1)),
      'sections': [
        for (final sec in Section.values)
          {
            'key': sec.key,
            'label': sec.label,
            'items': cards.where((c) => c['section'] == sec.key).toList(),
          }
      ],
      'strong_unmet': cards.where((c) => c['strong_unmet'] == true).toList(),
      'second_look': secondLook(cards, piles),
      'drift': ratingDrift(boothId, piles),
      'counts': {
        'met': cards.where((c) => c['section'] == 'met').length,
        'waited': cards.where((c) => c['section'] == 'waited').length,
        'sent': cards.where((c) => c['section'] == 'sent').length,
        'in_line': w.length,
      },
    };
  }

  Map<String, Object?> secondLook(List<Map<String, Object?>> cards, List<String> piles) => {
        'high_fit_low_pile': [
          for (final c in cards)
            if ((c['fit'] as double) >= 0.8 && isLowPile(piles, c['pile'] as String?))
              {'student_id': (c['student'] as Map)['id'], 'name': (c['student'] as Map)['name'], 'fit': c['fit'], 'pile': c['pile'],
               'prompt': 'Worth a second look at the resume?'}
        ],
        'low_fit_high_pile': [
          for (final c in cards)
            if ((c['fit'] as double) < 0.5 && isHighPile(piles, c['pile'] as String?))
              {'student_id': (c['student'] as Map)['id'], 'name': (c['student'] as Map)['name'], 'fit': c['fit'], 'pile': c['pile'],
               'prompt': 'Strong conversation. Check the resume against the role.'}
        ],
      };

  /// Information only: compares the share of top-two piles early vs late.
  Map<String, Object?>? ratingDrift(String boothId, List<String> piles) {
    final rows = db.all(
        'SELECT e.created_at, m.pile FROM exchanges e JOIN recruiter_marks m '
        'ON m.booth_id=e.booth_id AND m.student_id=e.student_id WHERE e.booth_id=? AND m.pile IS NOT NULL '
        'ORDER BY e.created_at', [boothId]);
    if (rows.length < 12) return null;
    final f = fair();
    final start = f['starts_at'] as int;
    final mid = start + ((f['ends_at'] as int) - start) ~/ 2;
    final early = rows.where((r) => (r['created_at'] as int) < mid).toList();
    final late = rows.where((r) => (r['created_at'] as int) >= mid).toList();
    if (early.length < 5 || late.length < 5) return null;
    double share(List<Row> xs) => xs.where((r) => isHighPile(piles, r['pile'] as String?)).length / xs.length;
    final se = share(early), sl = share(late);
    if (se - sl < 0.2) return null;
    final dt = DateTime.fromMillisecondsSinceEpoch(mid).toLocal();
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final label = '$h${dt.minute == 0 ? '' : ':${dt.minute.toString().padLeft(2, '0')}'} ${dt.hour < 12 ? 'am' : 'pm'}';
    return {
      'early_share': double.parse(se.toStringAsFixed(2)),
      'late_share': double.parse(sl.toStringAsFixed(2)),
      'message': 'Your ratings dropped after $label. Consider a quick second look at the afternoon list.',
    };
  }

  /// "Why am I here?": one receipt per recruiter list the student is in.
  List<Map<String, Object?>> receipts(String sid) {
    final ids = db
        .all('SELECT booth_id FROM exchanges WHERE student_id=? UNION SELECT booth_id FROM drops WHERE student_id=?', [sid, sid])
        .map((r) => r['booth_id'] as String);
    final out = <Map<String, Object?>>[];
    for (final bid in ids) {
      final ranked = rankBooth(bid);
      final c = ranked.firstWhere((r) => r.c.studentId == sid).c;
      out.add({'booth': publicBooth(booth(bid)), ...engine.receipt(bid, c, ranked)});
    }
    return out;
  }

  // ---------------------------------------------------------- pitches
  Map<String, Object?>? pitchFor(String sid, String boothId) {
    final r = db.one('SELECT * FROM pitches WHERE student_id=? AND booth_id=?', [sid, boothId]);
    if (r == null) return null;
    final j = (jd(r['json']) as Map).cast<String, Object?>();
    return {...j, 'history_count': (jd(r['history_json']) as List).length};
  }

  void savePitch(String sid, String boothId, Map<String, dynamic> p) {
    final cur = db.one('SELECT * FROM pitches WHERE student_id=? AND booth_id=?', [sid, boothId]);
    final hist = cur == null ? <Object?>[] : (jd(cur['history_json']) as List);
    if (cur != null) hist.add(jd(cur['json']));
    final lint = lintText(p['pitch'] as String? ?? '', question: p['question'] as String?);
    db.upsert('pitches', {
      'student_id': sid,
      'booth_id': boothId,
      'json': je({...p, 'lint': lint.toJson(), 'created_at': clock()}),
      'history_json': je(hist.length > 10 ? hist.sublist(hist.length - 10) : hist),
      'updated_at': clock(),
    }, ['student_id', 'booth_id']);
  }

  /// Student edited the pitch: save it and record the edit in the Voice
  /// Profile so future drafts follow their preferences.
  Map<String, Object?> editPitch(String sid, String boothId, String text, String? question) {
    final cur = pitchFor(sid, boothId);
    final before = (cur?['pitch'] as String?) ?? '';
    final lint = lintText(text, question: question ?? cur?['question'] as String?);
    final updated = {
      ...?cur?.cast<String, dynamic>(),
      'pitch': text.trim(),
      if (question != null) 'question': question.trim(),
      'source': 'edited',
      'edited': true,
    }..remove('history_count');
    savePitch(sid, boothId, updated);
    final vp = db.one('SELECT * FROM voice_profiles WHERE student_id=?', [sid]);
    final edits = ((jd(vp?['edits_json']) as List?) ?? []).toList();
    if (before.isNotEmpty && before.trim() != text.trim()) {
      edits.add({'before': before, 'after': text.trim(), 'at': clock()});
    }
    db.upsert('voice_profiles', {
      'student_id': sid,
      'transcript': vp?['transcript'],
      'answers_json': vp?['answers_json'],
      'profile_json': vp?['profile_json'],
      'edits_json': je(edits.length > 10 ? edits.sublist(edits.length - 10) : edits),
      'updated_at': clock(),
    }, ['student_id']);
    return {'pitch': pitchFor(sid, boothId), 'lint': lint.toJson()};
  }

  // ---------------------------------------------------------- rolodex
  List<Map<String, Object?>> rolodex(String sid) {
    final rows = db.all(
        'SELECT r.*, e.created_at AS met_at, e.method, e.asked_question FROM rolodex r '
        'LEFT JOIN exchanges e ON e.id=r.exchange_id WHERE r.student_id=? ORDER BY r.created_at DESC', [sid]);
    return [
      for (final r in rows)
        {
          'booth_id': r['booth_id'],
          'card': recruiterCard(booth(r['booth_id'] as String)),
          'booth': publicBooth(booth(r['booth_id'] as String)),
          'met_at': r['met_at'],
          'method': r['method'],
          'note': r['note'],
          'note_at': r['note_at'],
          'email': jd(r['email_json']),
          'email_sent_at': r['email_sent_at'],
          'asked_question': r['asked_question'] == 1,
        }
    ];
  }

  void rolodexNote(String sid, String boothId, String note) {
    final r = db.one('SELECT * FROM rolodex WHERE student_id=? AND booth_id=?', [sid, boothId]);
    if (r == null) throw ApiError(404, 'You have not met this booth yet.');
    db.exec('UPDATE rolodex SET note=?, note_at=? WHERE id=?', [note.trim(), clock(), r['id']]);
    game.onRolodexNote(sid, boothId);
    changed(['student:$sid']);
  }

  void askedQuestion(String sid, String boothId) {
    final ok = db.one('SELECT 1 FROM exchanges WHERE student_id=? AND booth_id=?', [sid, boothId]);
    if (ok == null) throw ApiError(404, 'Only after a confirmed conversation.');
    db.exec('UPDATE exchanges SET asked_question=1 WHERE student_id=? AND booth_id=?', [sid, boothId]);
    game.onAskedQuestion(sid, boothId);
    changed(['student:$sid']);
  }

  void emailSent(String sid, String boothId) {
    final r = db.one('SELECT * FROM rolodex WHERE student_id=? AND booth_id=?', [sid, boothId]);
    if (r == null) throw ApiError(404, 'Not in your rolodex.');
    if (r['email_sent_at'] == null) {
      db.exec('UPDATE rolodex SET email_sent_at=? WHERE id=?', [clock(), r['id']]);
      game.onFollowUp(sid, boothId);
    }
    changed(['student:$sid']);
  }

  // ---------------------------------------------------------- friends
  Map<String, Object?> addFriend(String sid, String code) {
    final fid = codes.verifyFriendCode(code) ??
        (db.one('SELECT 1 FROM students WHERE id=?', [code]) != null ? code : null);
    if (fid == null) throw ApiError(400, 'Not a QueueCue friend code.');
    if (fid == sid) throw ApiError(400, 'That is your own code.');
    final now = clock();
    db.upsert('friends', {'student_id': sid, 'friend_id': fid, 'created_at': now}, ['student_id', 'friend_id']);
    db.upsert('friends', {'student_id': fid, 'friend_id': sid, 'created_at': now}, ['student_id', 'friend_id']);
    changed(['student:$sid', 'student:$fid']);
    return {'friend': studentCard(student(fid))};
  }

  // ---------------------------------------------------------- business cards
  /// Random, unique 4-digit student card number (recruiters use 3 digits).
  int nextStudentNumber() {
    while (true) {
      final n = 1000 + rnd.nextInt(9000);
      if (db.one('SELECT 1 FROM students WHERE number=?', [n]) == null) return n;
    }
  }

  /// Student sends a friend request by number. Cards swap when accepted.
  Map<String, Object?> friendRequest(String sid, int number) {
    final to = db.one('SELECT * FROM students WHERE number=?', [number]);
    if (to == null) {
      final rb = db.one('SELECT id FROM booths WHERE recruiter_number=? OR number=?', [number, number]);
      if (rb != null) return boothCardRequest(sid, rb['id'] as String);
      throw ApiError(404, 'No one has number $number.');
    }
    if (to['id'] == sid) throw ApiError(400, 'That is your own number.');
    if (db.one('SELECT 1 FROM friends WHERE student_id=? AND friend_id=?', [sid, to['id']]) != null) {
      throw ApiError(409, 'You and ${to['name']} already swapped cards.');
    }
    // If they already asked me, accepting is the natural thing.
    final reverse = db.one(
        "SELECT id FROM card_requests WHERE kind='friend' AND from_student=? AND to_student=? AND status='pending'",
        [to['id'], sid]);
    if (reverse != null) return respondFriend(sid, reverse['id'] as int, true);
    final dup = db.one(
        "SELECT id FROM card_requests WHERE kind='friend' AND from_student=? AND to_student=? AND status='pending'",
        [sid, to['id']]);
    if (dup == null) {
      db.insert('card_requests',
          {'kind': 'friend', 'from_student': sid, 'to_student': to['id'], 'status': 'pending', 'created_at': clock()});
    }
    changed(['student:$sid', 'student:${to['id']}']);
    return {'message': 'Request sent to #$number. Cards appear when ${to['name']} accepts.'};
  }

  Map<String, Object?> respondFriend(String sid, int requestId, bool accept) {
    final r = db.one("SELECT * FROM card_requests WHERE id=? AND kind='friend' AND to_student=? AND status='pending'",
        [requestId, sid]);
    if (r == null) throw ApiError(404, 'Request not found.');
    final now = clock();
    db.exec('UPDATE card_requests SET status=?, resolved_at=? WHERE id=?', [accept ? 'accepted' : 'declined', now, requestId]);
    final other = r['from_student'] as String;
    if (accept) {
      db.upsert('friends', {'student_id': sid, 'friend_id': other, 'created_at': now}, ['student_id', 'friend_id']);
      db.upsert('friends', {'student_id': other, 'friend_id': sid, 'created_at': now}, ['student_id', 'friend_id']);
    }
    changed(['student:$sid', 'student:$other']);
    final o = student(other);
    return {'message': accept ? 'Cards swapped with ${o['name']}.' : 'Declined.', 'card': accept ? studentCard(o) : null};
  }

  /// Student taps "Send my card to the recruiter" at a booth. The recruiter
  /// accepts on their device, which is what verifies the conversation.
  Map<String, Object?> boothCardRequest(String sid, String boothId) {
    final b = booth(boothId);
    if (db.one('SELECT 1 FROM exchanges WHERE booth_id=? AND student_id=?', [boothId, sid]) != null) {
      throw ApiError(409, 'You already swapped cards with ${b['name']}.');
    }
    checkIn(sid);
    final dup = db.one("SELECT id FROM card_requests WHERE kind='booth' AND from_student=? AND booth_id=? AND status='pending'",
        [sid, boothId]);
    if (dup == null) {
      db.insert('card_requests',
          {'kind': 'booth', 'from_student': sid, 'booth_id': boothId, 'status': 'pending', 'created_at': clock()});
    }
    changed(['student:$sid', 'booth:$boothId']);
    return {'message': 'Card sent to ${b['recruiter_name'] ?? b['name']}. It swaps when they tap Accept.'};
  }

  Map<String, Object?> respondBooth(String boothId, int requestId, bool accept, {bool group = false, String? pile, String? memory}) {
    final r = db.one("SELECT * FROM card_requests WHERE id=? AND kind='booth' AND booth_id=? AND status='pending'",
        [requestId, boothId]);
    if (r == null) throw ApiError(404, 'Request not found.');
    Map<String, Object?> res = {'message': 'Declined.'};
    if (accept) {
      res = confirm(boothId, studentId: r['from_student'] as String, fromRequest: true, group: group, pile: pile, memory: memory);
    }
    db.exec('UPDATE card_requests SET status=?, resolved_at=? WHERE id=?', [accept ? 'accepted' : 'declined', clock(), requestId]);
    changed(['student:${r['from_student']}', 'booth:$boothId']);
    return res;
  }

  List<Map<String, Object?>> boothRequests(String boothId) => [
        for (final r in db.all(
            "SELECT * FROM card_requests WHERE kind='booth' AND booth_id=? AND status='pending' ORDER BY created_at", [boothId]))
          {
            'id': r['id'],
            'at': r['created_at'],
            'student': studentCard(student(r['from_student'] as String)),
            'in_line': waiting(boothId).any((e) => e['student_id'] == r['from_student']),
          }
      ];

  Map<String, Object?> cardBook(String sid) {
    final me = student(sid);
    return {
      'me': studentCard(me),
      'incoming': [
        for (final r in db.all(
            "SELECT * FROM card_requests WHERE kind='friend' AND to_student=? AND status='pending' ORDER BY created_at DESC", [sid]))
          {'id': r['id'], 'at': r['created_at'], 'card': studentCard(student(r['from_student'] as String))}
      ],
      'outgoing': [
        for (final r in db.all(
            "SELECT * FROM card_requests WHERE from_student=? AND status='pending' ORDER BY created_at DESC", [sid]))
          r['kind'] == 'friend'
              ? {'kind': 'friend', 'card': studentCard(student(r['to_student'] as String))}
              : {'kind': 'booth', 'booth': publicBooth(booth(r['booth_id'] as String))}
      ],
      'friends': [
        for (final f in db.all('SELECT s.* FROM friends f JOIN students s ON s.id=f.friend_id WHERE f.student_id=? ORDER BY f.created_at DESC', [sid]))
          studentCard(f)
      ],
      'recruiters': [
        for (final r in db.all('SELECT booth_id, created_at FROM exchanges WHERE student_id=? ORDER BY created_at DESC', [sid]))
          {...recruiterCard(booth(r['booth_id'] as String)), 'met_at': r['created_at']}
      ],
    };
  }

  // ---------------------------------------------------------- recruiter cards
  /// Recruiter shares their card by number: another recruiter (peer request)
  /// or a student (counts as meeting them, verified by this recruiter device).
  Map<String, Object?> recruiterShare(String boothId, int number, {bool group = false}) {
    final peer = db.one('SELECT * FROM booths WHERE recruiter_number=?', [number]);
    if (peer != null) {
      if (peer['id'] == boothId) throw ApiError(400, 'That is your own number.');
      if (db.one('SELECT 1 FROM recruiter_peers WHERE booth_id=? AND peer_booth_id=?', [boothId, peer['id']]) != null) {
        throw ApiError(409, 'You already swapped cards with ${peer['recruiter_name']}.');
      }
      final reverse = db.one("SELECT id FROM card_requests WHERE kind='peer' AND booth_id=? AND from_student=? AND status='pending'",
          [boothId, peer['id']]);
      if (reverse != null) return respondPeer(boothId, reverse['id'] as int, true);
      if (db.one("SELECT 1 FROM card_requests WHERE kind='peer' AND from_student=? AND booth_id=? AND status='pending'",
              [boothId, peer['id']]) ==
          null) {
        // from_student holds the sending booth id for peer requests; booth_id is the receiver.
        db.insert('card_requests', {'kind': 'peer', 'from_student': boothId, 'booth_id': peer['id'], 'status': 'pending', 'created_at': clock()});
      }
      changed(['booth:$boothId', 'booth:${peer['id']}']);
      return {'message': 'Request sent to ${peer['recruiter_name']} (${peer['name']}). Cards appear when they accept.'};
    }
    return confirm(boothId, number: number, group: group);
  }

  Map<String, Object?> respondPeer(String boothId, int requestId, bool accept) {
    final r = db.one("SELECT * FROM card_requests WHERE id=? AND kind='peer' AND booth_id=? AND status='pending'", [requestId, boothId]);
    if (r == null) throw ApiError(404, 'Request not found.');
    final other = r['from_student'] as String;
    final now = clock();
    db.exec('UPDATE card_requests SET status=?, resolved_at=? WHERE id=?', [accept ? 'accepted' : 'declined', now, requestId]);
    if (accept) {
      db.upsert('recruiter_peers', {'booth_id': boothId, 'peer_booth_id': other, 'created_at': now}, ['booth_id', 'peer_booth_id']);
      db.upsert('recruiter_peers', {'booth_id': other, 'peer_booth_id': boothId, 'created_at': now}, ['booth_id', 'peer_booth_id']);
    }
    changed(['booth:$boothId', 'booth:$other']);
    return {'message': accept ? 'Cards swapped with ${booth(other)['recruiter_name']}.' : 'Declined.'};
  }

  Map<String, Object?> recruiterCardBook(String boothId) {
    final b = booth(boothId);
    return {
      'me': recruiterCard(b),
      'incoming_peers': [
        for (final r in db.all("SELECT * FROM card_requests WHERE kind='peer' AND booth_id=? AND status='pending' ORDER BY created_at DESC", [boothId]))
          {'id': r['id'], 'card': recruiterCard(booth(r['from_student'] as String))}
      ],
      'incoming_students': boothRequests(boothId),
      'outgoing': [
        for (final r in db.all("SELECT * FROM card_requests WHERE kind='peer' AND from_student=? AND status='pending'", [boothId]))
          recruiterCard(booth(r['booth_id'] as String))
      ],
      'peers': [
        for (final p in db.all('SELECT peer_booth_id FROM recruiter_peers WHERE booth_id=? ORDER BY created_at DESC', [boothId]))
          recruiterCard(booth(p['peer_booth_id'] as String))
      ],
      'students': [
        for (final e in db.all('SELECT e.*, m.stars, m.pile, m.tags_json, m.memory_note FROM exchanges e '
            'LEFT JOIN recruiter_marks m ON m.booth_id=e.booth_id AND m.student_id=e.student_id '
            'WHERE e.booth_id=? ORDER BY e.created_at DESC', [boothId]))
          {
            ...studentCard(student(e['student_id'] as String)),
            'met_at': e['created_at'],
            'stars': e['stars'],
            'pile': e['pile'],
            'tags': jd(e['tags_json']) ?? const [],
            'memory_note': e['memory_note'],
            'fit_pct': (((fit(e['student_id'] as String, boothId)?['fit'] as num?) ?? 0) * 100).round(),
          }
      ],
    };
  }

  // ---------------------------------------------------------- route
  /// Optimal walk: the best stops (eligible, good fit, worth the wait),
  /// visited in order along the line of tents from the entrance. On a line,
  /// a single pass with no backtracking is the shortest walk.
  Map<String, Object?> route(String sid, {int maxStops = 5}) {
    final s = student(sid);
    final cands = <Map<String, Object?>>[];
    for (final b in booths()) {
      final bid = b['id'] as String;
      if (b['status'] != 'open') continue;
      final f = fit(sid, bid);
      if (f == null) continue;
      final el = eligibility(s, b);
      final met = db.one('SELECT 1 FROM exchanges WHERE booth_id=? AND student_id=?', [bid, sid]) != null;
      final fv = (f['fit'] as num).toDouble();
      final est = WaitEstimate.of(waiting(bid).length, avgServiceMin(bid));
      final waitMid = (est.lowMin + est.highMin) / 2;
      cands.add({
        'booth': publicBooth(b),
        'fit': fv,
        'fit_pct': (fv * 100).round(),
        'eligible': el['eligible'],
        'met': met,
        'wait_label': est.ahead == 0 ? 'no wait' : est.label,
        'wait_mid': waitMid,
        'reason': f['reason'],
        'resume_label': resume(f['resume_id'] as String?)?['label'],
        'value': fv - 0.004 * waitMid,
      });
    }
    final pool = cands.where((c) => c['eligible'] == true && c['met'] != true && (c['fit'] as double) >= 0.6).toList()
      ..sort((a, c) => (c['value'] as double).compareTo(a['value'] as double));
    final stops = pool.take(maxStops).toList()
      ..sort((a, c) => ((a['booth'] as Map)['x'] as int).compareTo((c['booth'] as Map)['x'] as int));
    for (var i = 0; i < stops.length; i++) {
      stops[i]['step'] = i + 1;
    }
    const metersPerTent = 15;
    final lastX = stops.isEmpty ? 0 : (stops.last['booth'] as Map)['x'] as int;
    final walkM = lastX * metersPerTent;
    final waitTotal = stops.fold<double>(0, (a, c) => a + (c['wait_mid'] as double));
    return {
      'stops': stops,
      'tents': cands,
      'walk_meters': walkM,
      'walk_min': (walkM / 70).ceil(),
      'wait_min': waitTotal.round(),
      'talk_min': stops.length * 4,
      'total_min': ((walkM / 70).ceil() + waitTotal + stops.length * 4).round(),
      'explain': 'Your best ${stops.length} stops by fit, minus a little for long lines, visited in order from the entrance so you never walk back.',
    };
  }

  // ---------------------------------------------------------- accessibility
  Map<String, Object?> accessRequest(String sid, String? boothId, String need) {
    final id = db.insert('access_requests', {
      'student_id': sid,
      'booth_id': boothId,
      'need': need.trim().isEmpty ? 'Assistance requested' : need.trim(),
      'status': 'open',
      'created_at': clock(),
    });
    db.exec('UPDATE students SET accommodation=1 WHERE id=?', [sid]);
    changed(['organizer', 'student:$sid']);
    final b = boothId == null ? null : booth(boothId);
    return {
      'id': id,
      'message': b == null
          ? 'Sent to organizer staff. Someone is on the way to the help desk.'
          : 'Sent to organizer staff with your location: Booth ${b['number']} (${b['name']}).',
    };
  }

  /// Offline summary written synchronously (simulated students only, so the
  /// crowd never occupies the live model).
  void offlineSummary(String boothId, String sid, String resumeId) {
    final r = resume(resumeId);
    if (r == null) return;
    final sum = offline.summarySync(
        boothCtx(booth(boothId)),
        ResumeCtx(id: resumeId, label: r['label'] as String, blindText: r['blind_text'] as String));
    db.upsert('summaries', {
      'booth_id': boothId,
      'student_id': sid,
      'resume_id': resumeId,
      'json': je(sum),
      'updated_at': clock(),
    }, ['booth_id', 'student_id', 'resume_id']);
  }

  String fmtWorkAuth(String w) => workAuthLabels[w] ?? w;

  static String jsonPretty(Object? o) => const JsonEncoder.withIndent('  ').convert(o);

  OfflineAi get offline => ai.cached.offline;
}
