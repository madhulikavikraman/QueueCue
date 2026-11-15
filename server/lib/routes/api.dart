import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../ai/lint.dart';
import '../ai/ollama_ai_service.dart';
import '../core/close_audit.dart';
import '../core/qq.dart';
import '../db/db.dart';
import '../fairness/fairness_engine.dart';
import '../seed/seeder.dart';
import '../util/blind.dart';
import '../util/codes.dart';
import '../util/passwords.dart';
import '../util/pdf_text.dart';
import 'http_util.dart';

Router buildApi(QQ qq) {
  final r = Router();
  final db = qq.db;

  // ================================================================= public
  r.get('/api/health', (Request req) async {
    final o = await OllamaAiService.check(qq.cfg.ollamaUrl, qq.cfg.model);
    return jsonOk({
      'ok': true,
      'model': qq.cfg.model,
      'ollama_up': o.up,
      'model_pulled': o.hasModel,
      'whisper': await qq.whisper.available(),
      'ai_live': qq.aiLive,
      'demo_mode': qq.demoMode,
      'clients': qq.hub.count,
    });
  });

  r.get('/api/fair', (Request req) {
    final f = qq.fair();
    final st = qq.settings();
    return jsonOk({
      'id': f['id'],
      'name': f['name'],
      'venue': f['venue'],
      'status': f['status'],
      'starts_at': f['starts_at'],
      'ends_at': f['ends_at'],
      'seed_hash': f['seed_hash'],
      'seed': f['status'] == 'closed' ? f['seed'] : null,
      'settings': {'w_fit': st.wFit, 'w_effort': st.wEffort, 'cap_min': st.capMin, 'formula': st.formula},
      'demo_mode': qq.demoMode,
      'ai_live': qq.aiLive,
      'floor_w': f['floor_w'],
      'floor_h': f['floor_h'],
      'booths': [
        for (final b in qq.booths())
          {
            ...qq.publicBooth(b),
            'line': qq.waiting(b['id'] as String).length,
            'estimate': WaitEstimate.of(qq.waiting(b['id'] as String).length, qq.avgServiceMin(b['id'] as String)).toJson(),
          }
      ],
    });
  });

  // ================================================================= demo
  r.get('/api/demo/personas', (Request req) {
    if (!qq.demoMode) return jsonOk({'personas': []});
    final data = Seeder(qq).loadSeed();
    return jsonOk({
      'personas': [
        for (final ps in data['personas'] as List)
          {
            'persona': ps['persona'],
            'name': ps['name'],
            'label': ps['label'],
            'avatar': ps['avatar'],
            'token': Seeder.demoToken(ps['persona'] as String),
          }
      ],
      'booth_links': [
        for (final b in qq.booths())
          {'id': b['id'], 'name': b['name'], 'number': b['number'], 'key': b['booth_key'], 'recruiter': b['recruiter_name']}
      ],
      'organizer_key': qq.cfg.organizerKey,
    });
  });

  /// Demo Mode only: the ten showcase students and the points engine at work.
  r.get('/api/demo/showcase', (Request req) {
    if (!qq.demoMode) throw ApiError(404, 'Showcase is only available in Demo Mode.');
    const ruleLabels = {
      'conversation': 'Verified conversation',
      'asked_question': 'Asked their pitch question',
      'drop': 'Resume drop (by fit)',
      'matched_resume': 'Used the matched resume',
      'rolodex_note': 'Note within 10 min',
      'follow_up': 'Follow-up within 24 h',
      'off_beaten': 'Off the beaten booth',
      'early_bird': 'Early Bird',
    };
    final out = <Map<String, Object?>>[];
    for (final sc in Seeder.showcase) {
      final first = (sc[0] as String).split(' ').first.toLowerCase();
      final s = db.one('SELECT * FROM students WHERE id=?', ['stu-$first']);
      if (s == null) continue;
      final sid = s['id'] as String;
      final pts = qq.game.totalPoints(sid);
      final ledger = db.all(
          'SELECT p.rule, p.points, p.award_at, b.name AS booth FROM points p LEFT JOIN booths b ON b.id=p.booth_id WHERE p.student_id=? ORDER BY p.created_at',
          [sid]);
      out.add({
        'card': qq.studentCard(s),
        'token': s['token'],
        'points': pts,
        'pending': qq.game.pendingPoints(sid),
        'level': qq.game.level(pts),
        'ledger': [
          for (final l in ledger)
            {'rule': ruleLabels[l['rule']] ?? l['rule'], 'points': l['points'], 'booth': l['booth'], 'pending': (l['award_at'] as int) > qq.clock()}
        ],
        'met': [
          for (final e in db.all('SELECT e.booth_id, e.created_at FROM exchanges e WHERE e.student_id=? ORDER BY e.created_at', [sid]))
            {...qq.recruiterCard(qq.booth(e['booth_id'] as String)), 'met_at': e['created_at']}
        ],
        'dropped': [
          for (final d in db.all("SELECT b.name, b.number FROM drops d JOIN booths b ON b.id=d.booth_id WHERE d.student_id=? AND d.kind='drop'", [sid]))
            {'name': d['name'], 'number': d['number']}
        ],
        'friends': db.scalar('SELECT COUNT(*) FROM friends WHERE student_id=?', [sid]),
        'badges': db.all('SELECT badge FROM badges WHERE student_id=?', [sid]).map((b) => b['badge']).toList(),
      });
    }
    out.sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
    return jsonOk({'students': out, 'recruiters': [for (final id in Seeder.showcaseBooths) qq.recruiterCard(qq.booth(id))]});
  });

  // ================================================================= student: onboarding
  r.post('/api/students', (Request req) async {
    final j = await readJson(req);
    final name = (j['name'] as String? ?? '').trim();
    final major = (j['major'] as String? ?? '').trim();
    final auth = j['work_auth'] as String? ?? '';
    final email = (j['email'] as String? ?? '').trim().toLowerCase();
    final password = j['password'] as String? ?? '';
    if (email.isEmpty || !email.contains('@')) throw ApiError(400, 'Enter your email; it is how you sign back in.');
    if (password.length < 4) throw ApiError(400, 'Choose a password of at least 4 characters.');
    // Same email again: sign back in to the saved account instead of duplicating it.
    final existing = db.one('SELECT * FROM students WHERE lower(email)=? AND is_sim=0', [email]);
    if (existing != null) {
      if (!checkPassword(password, existing['password_hash'] as String?)) {
        throw ApiError(409, 'That email already has an account. Use its password to continue where you left off.', {'exists': true});
      }
      return jsonOk({'id': existing['id'], 'token': existing['token'], 'number': existing['number'], 'resumed': true});
    }
    if (name.isEmpty || major.isEmpty) throw ApiError(400, 'Name and major are required.');
    if (!workAuthLabels.containsKey(auth)) throw ApiError(400, 'Pick a work authorization option.');
    final id = 'stu-${Codes.randomToken(8)}';
    final token = Codes.randomToken(24);
    db.insert('students', {
      'id': id,
      'fair_id': qq.fairId,
      'token': token,
      'name': name,
      'email': email,
      'password_hash': hashPassword(password),
      'linkedin': (j['linkedin'] as String?)?.trim(),
      'major': major,
      'degree': (j['degree'] as String?)?.trim() ?? '',
      'grad_year': j['grad_year'] is int ? j['grad_year'] : int.tryParse('${j['grad_year']}'),
      'work_auth': auth,
      'avatar': j['avatar'] as String? ?? 'fox',
      'number': qq.nextStudentNumber(),
      'interests': (j['interests'] as String?)?.trim(),
      'bio': (j['bio'] as String?)?.trim(),
      'created_at': qq.clock(),
    });
    return jsonOk({'id': id, 'token': token, 'number': qq.student(id)['number']});
  });

  Map<String, Object?> me(Row s) {
    final sid = s['id'] as String;
    final vp = db.one('SELECT transcript, profile_json, updated_at FROM voice_profiles WHERE student_id=?', [sid]);
    final q = db.one(
        "SELECT q.booth_id FROM queue_entries q WHERE q.student_id=? AND q.status='waiting'", [sid]);
    return {
      'id': sid,
      'number': s['number'],
      'interests': s['interests'],
      'bio': s['bio'],
      'name': s['name'],
      'email': s['email'],
      'linkedin': s['linkedin'],
      'major': s['major'],
      'degree': s['degree'],
      'grad_year': s['grad_year'],
      'work_auth': s['work_auth'],
      'work_auth_label': qq.fmtWorkAuth(s['work_auth'] as String),
      'avatar': s['avatar'],
      'persona': s['persona'],
      'checked_in_at': s['checked_in_at'],
      'onboarded': s['onboarded'] == 1,
      'voice_skipped': s['voice_skipped'] == 1,
      'has_voice': vp?['profile_json'] != null,
      'voice_profile': jd(vp?['profile_json']),
      'leaderboard_opt_in': s['leaderboard_opt_in'] == 1,
      'accommodation': s['accommodation'] == 1,
      'current_line': q?['booth_id'],
      'resumes': [
        for (final x in qq.resumes(sid))
          {
            'id': x['id'],
            'label': x['label'],
            'filename': x['filename'],
            'is_default': x['is_default'] == 1,
            'chars': (x['text'] as String).length,
            'parsed': x['parsed_json'] != null,
          }
      ],
      'fair_status': qq.fair()['status'],
    };
  }

  r.get('/api/me', (Request req) => jsonOk(me(requireStudent(qq, req))));

  r.post('/api/students/login', (Request req) async {
    final j = await readJson(req);
    final email = (j['email'] as String? ?? '').trim().toLowerCase();
    final s = db.one('SELECT * FROM students WHERE lower(email)=? AND is_sim=0', [email]);
    if (s == null || !checkPassword(j['password'] as String? ?? '', s['password_hash'] as String?)) {
      throw ApiError(401, 'Email or password is wrong.');
    }
    return jsonOk({'token': s['token'], 'name': s['name'], 'onboarded': s['onboarded'] == 1});
  });

  r.post('/api/recruiter/signup', (Request req) async {
    final j = await readJson(req);
    if ((j['code'] as String? ?? '').trim().toUpperCase() != qq.cfg.recruiterSignupCode.toUpperCase()) {
      throw ApiError(403, 'That fair code is not right. Use the code the organizer emailed you.');
    }
    final name = (j['name'] as String? ?? '').trim();
    final email = (j['email'] as String? ?? '').trim().toLowerCase();
    final password = j['password'] as String? ?? '';
    final company = (j['company'] as String? ?? '').trim();
    if (name.isEmpty || company.isEmpty || !email.contains('@')) throw ApiError(400, 'Name, work email and company are required.');
    if (password.length < 4) throw ApiError(400, 'Choose a password of at least 4 characters.');
    final dupEmail = db.one('SELECT * FROM booths WHERE lower(recruiter_email)=?', [email]);
    if (dupEmail != null) {
      if (checkPassword(password, dupEmail['recruiter_password'] as String?)) {
        return jsonOk({'booth_id': dupEmail['id'], 'key': dupEmail['booth_key'], 'name': dupEmail['recruiter_name'],
            'company': dupEmail['name'], 'number': dupEmail['recruiter_number'], 'resumed': true});
      }
      throw ApiError(409, 'That email already has an account. Sign in instead.');
    }
    if (db.one('SELECT 1 FROM booths WHERE lower(name)=?', [company.toLowerCase()]) != null) {
      throw ApiError(409, '$company already has a booth. Ask your colleague to share their sign-in, or use a team name like "$company (Team 2)".');
    }
    final number = ((db.scalar('SELECT MAX(number) FROM booths') as int?) ?? 0) + 1;
    var id = company.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    if (id.isEmpty || db.one('SELECT 1 FROM booths WHERE id=?', [id]) != null) id = '$id-$number';
    final role = (j['role'] as String? ?? '').trim();
    final about = (j['about'] as String? ?? '').trim();
    final majors = ((j['majors'] as List?) ?? const []).map((e) => '$e').toList();
    int recNumber;
    do {
      recNumber = 100 + qq.rnd.nextInt(900);
    } while (db.one('SELECT 1 FROM booths WHERE recruiter_number=?', [recNumber]) != null ||
        db.one('SELECT 1 FROM students WHERE number=?', [recNumber]) != null);
    db.insert('booths', {
      'id': id,
      'fair_id': qq.fairId,
      'number': number,
      'name': company,
      'tagline': about.isEmpty ? 'Hiring at the fair' : about,
      'category': (j['category'] as String? ?? 'Employer').trim(),
      'about': about,
      'roles_json': je([
        {'title': role.isEmpty ? 'General hiring' : role, 'desc': about.isEmpty ? (role.isEmpty ? 'General hiring' : role) : about,
         'skills': (j['skills'] as List? ?? const []).map((e) => '$e'.toLowerCase()).toList()}
      ]),
      'sponsors': ['yes', 'no', 'unknown'].contains(j['sponsors']) ? j['sponsors'] : 'unknown',
      'majors_json': je(majors.isEmpty ? ['Computer Science', 'Computer Engineering', 'Electrical Engineering', 'Data Science'] : majors),
      'partial_majors_json': '[]',
      'citizenship_required': j['citizenship_required'] == true ? 1 : 0,
      'x': number,
      'y': 1,
      'booth_key': 'bk-${Codes.randomToken(10)}',
      'recruiter_name': name,
      'recruiter_email': email,
      'recruiter_password': hashPassword(password),
      'recruiter_title': (j['title'] as String? ?? 'Recruiter').trim(),
      'recruiter_number': recNumber,
      'default_service_min': 4,
    });
    db.exec('UPDATE fairs SET floor_w=MAX(floor_w, ?)', [number + 2]);
    // Score every student for the new booth (simulated students instantly, real ones as a job).
    for (final s in db.all('SELECT id, is_sim FROM students')) {
      if (s['is_sim'] == 1) {
        await qq.computeFit(s['id'] as String, id);
      }
    }
    qq.jobs.start('booth_fits', boothId: id, run: (jb) async {
      for (final s in db.all('SELECT id FROM students WHERE is_sim=0')) {
        if (qq.resumes(s['id'] as String).isNotEmpty) await qq.computeFit(s['id'] as String, id);
      }
      qq.changed(['fair']);
      return null;
    });
    qq.changed(['fair', 'organizer']);
    final b = qq.booth(id);
    return jsonOk({'booth_id': id, 'key': b['booth_key'], 'name': name, 'company': company, 'number': recNumber, 'tent': number});
  });

  r.patch('/api/me', (Request req) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    final allowed = ['name', 'email', 'linkedin', 'major', 'degree', 'grad_year', 'work_auth', 'avatar', 'interests', 'bio'];
    for (final k in allowed) {
      if (j.containsKey(k)) db.exec('UPDATE students SET $k=? WHERE id=?', [j[k], s['id']]);
    }
    if (j['leaderboard_opt_in'] != null) {
      db.exec('UPDATE students SET leaderboard_opt_in=? WHERE id=?', [j['leaderboard_opt_in'] == true ? 1 : 0, s['id']]);
    }
    qq.changed(['student:${s['id']}']);
    return jsonOk(me(qq.student(s['id'] as String)));
  });

  /// Upload a resume: { label, filename, pdf_base64 } or { label, text }.
  r.post('/api/me/resumes', (Request req) async {
    final s = requireStudent(qq, req);
    final sid = s['id'] as String;
    final j = await readJson(req);
    final label = (j['label'] as String? ?? '').trim();
    if (label.isEmpty) throw ApiError(400, 'Give this resume a label, e.g. "AI/ML".');
    if (qq.resumes(sid).length >= 4) throw ApiError(400, 'Up to 4 resumes.');
    if (qq.resumes(sid).any((x) => (x['label'] as String).toLowerCase() == label.toLowerCase())) {
      throw ApiError(400, 'You already have a resume labelled "$label".');
    }
    final rid = 'r-${Codes.randomToken(8)}';
    String text = (j['text'] as String? ?? '').trim();
    String? pdfPath;
    if (j['pdf_base64'] is String) {
      final bytes = base64Decode(j['pdf_base64'] as String);
      if (bytes.length > 8 * 1024 * 1024) throw ApiError(400, 'PDF is over 8 MB.');
      if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw ApiError(400, 'That file is not a PDF.');
      }
      final dir = qq.cfg.resolve(qq.cfg.uploadsDir);
      Directory(dir).createSync(recursive: true);
      pdfPath = p.join(dir, '$rid.pdf');
      File(pdfPath).writeAsBytesSync(bytes);
      text = await extractPdfText(pdfPath);
      if (text.length < 80) {
        throw ApiError(422, 'Could not read text from this PDF (it may be a scanned image). Paste your resume text instead.',
            {'needs_text': true});
      }
    }
    if (text.length < 80) throw ApiError(400, 'Resume text looks too short.');
    final isFirst = qq.resumes(sid).isEmpty;
    db.insert('resumes', {
      'id': rid,
      'student_id': sid,
      'label': label,
      'filename': j['filename'] as String?,
      'pdf_path': pdfPath,
      'text': text,
      'blind_text': blindResume(text, nameTokens: (s['name'] as String).split(' ')),
      'is_default': isFirst ? 1 : 0,
      'created_at': qq.clock(),
    });
    db.exec('DELETE FROM fits WHERE student_id=?', [sid]);
    qq.changed(['student:$sid']);
    return jsonOk({'id': rid, 'chars': text.length, 'preview': text.length > 400 ? '${text.substring(0, 400)}…' : text});
  });

  r.delete('/api/me/resumes/<rid>', (Request req, String rid) {
    final s = requireStudent(qq, req);
    final x = qq.resume(rid);
    if (x == null || x['student_id'] != s['id']) throw ApiError(404, 'Not found');
    db.exec('DELETE FROM resumes WHERE id=?', [rid]);
    if (x['is_default'] == 1) {
      db.exec('UPDATE resumes SET is_default=1 WHERE id=(SELECT id FROM resumes WHERE student_id=? ORDER BY created_at LIMIT 1)', [s['id']]);
    }
    return jsonOk({'ok': true});
  });

  r.post('/api/me/resumes/<rid>/default', (Request req, String rid) {
    final s = requireStudent(qq, req);
    final x = qq.resume(rid);
    if (x == null || x['student_id'] != s['id']) throw ApiError(404, 'Not found');
    db.exec('UPDATE resumes SET is_default=(id=?) WHERE student_id=?', [rid, s['id']]);
    return jsonOk({'ok': true});
  });

  /// Voice profile: { wav_base64, answers[] } or { transcript, answers[] }.
  r.post('/api/me/voice', (Request req) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    final answers = ((j['answers'] as List?) ?? const []).map((e) => '$e').where((e) => e.trim().isNotEmpty).toList();
    String? wav;
    if (j['wav_base64'] is String) {
      final dir = qq.cfg.resolve(p.join(qq.cfg.uploadsDir, 'audio'));
      Directory(dir).createSync(recursive: true);
      wav = p.join(dir, '${s['id']}-${qq.clock()}.wav');
      File(wav).writeAsBytesSync(base64Decode(j['wav_base64'] as String));
    }
    final id = qq.jobs.voice(s['id'] as String,
        wavPath: wav, transcript: j['transcript'] as String?, answers: answers);
    return jsonOk({'job_id': id});
  });

  r.post('/api/me/voice/skip', (Request req) {
    final s = requireStudent(qq, req);
    db.exec('UPDATE students SET voice_skipped=1 WHERE id=?', [s['id']]);
    return jsonOk({'ok': true, 'message': 'Skipped. Pitches will be plainer until you add your voice.'});
  });

  /// Finish onboarding: parse resumes + score every booth (background job).
  r.post('/api/me/onboard', (Request req) {
    final s = requireStudent(qq, req);
    if (qq.resumes(s['id'] as String).isEmpty) throw ApiError(400, 'Upload at least one resume.');
    db.exec('UPDATE students SET onboarded=1 WHERE id=?', [s['id']]);
    return jsonOk({'job_id': qq.jobs.onboard(s['id'] as String)});
  });

  r.post('/api/me/checkin', (Request req) {
    final s = requireStudent(qq, req);
    qq.checkIn(s['id'] as String);
    return jsonOk({'ok': true});
  });

  r.get('/api/jobs/<id>', (Request req, String id) => jsonOk(qq.jobs.get(id) ?? (throw ApiError(404, 'Job not found'))));

  // ================================================================= student: plan & booths
  r.get('/api/me/plan', (Request req) {
    final s = requireStudent(qq, req);
    final sid = s['id'] as String;
    final plan = qq.plan(sid);
    final job = qq.jobs.latest(sid, 'onboard') ?? qq.jobs.latest(sid, 'plan');
    return jsonOk({...plan, 'job': job != null && job['status'] != 'done' ? job : null});
  });

  r.post('/api/me/plan/refresh', (Request req) {
    final s = requireStudent(qq, req);
    return jsonOk({'job_id': qq.jobs.plan(s['id'] as String)});
  });

  r.get('/api/booths/<bid>/me', (Request req, String bid) {
    final s = requireStudent(qq, req);
    final sid = s['id'] as String;
    final b = qq.booth(bid);
    final f = qq.fit(sid, bid);
    final drop = db.one("SELECT * FROM drops WHERE booth_id=? AND student_id=? AND kind='drop'", [bid, sid]);
    final ex = db.one('SELECT * FROM exchanges WHERE booth_id=? AND student_id=?', [bid, sid]);
    final job = qq.jobs.latest(sid, 'pitch', boothId: bid);
    return jsonOk({
      'booth': qq.publicBooth(b),
      'fit': f?['fit'],
      'fit_pct': f == null ? null : ((f['fit'] as num) * 100).round(),
      'reason': f?['reason'],
      'resume_id': f?['resume_id'],
      'resume_label': qq.resume(f?['resume_id'] as String?)?['label'],
      'resume_reason': f?['resume_reason'],
      ...qq.eligibility(s, b),
      'line': qq.lineState(bid, sid),
      'dropped': drop == null ? null : {'at': drop['created_at'], 'resume_id': drop['resume_id'], 'note': drop['note']},
      'met': ex == null ? null : {'at': ex['created_at'], 'asked_question': ex['asked_question'] == 1},
      'pitch': qq.pitchFor(sid, bid),
      'card_sent': db.one("SELECT created_at FROM card_requests WHERE kind='booth' AND from_student=? AND booth_id=? AND status='pending'", [sid, bid])?['created_at'],
      'pitch_job': job != null && job['status'] != 'done' ? job : null,
      'fair_status': qq.fair()['status'],
      'join_token_ok': qq.codes.verifyBoothJoin(bid, req.url.queryParameters['t']),
      'demo_mode': qq.demoMode,
      'ai_live': qq.aiLive,
    });
  });

  r.post('/api/booths/<bid>/join', (Request req, String bid) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    final st = qq.join(s['id'] as String, bid, token: j['t'] as String?, resumeId: j['resume_id'] as String?);
    if (qq.pitchFor(s['id'] as String, bid) == null) qq.jobs.pitch(s['id'] as String, bid);
    return jsonOk(st);
  });

  r.post('/api/booths/<bid>/leave', (Request req, String bid) {
    final s = requireStudent(qq, req);
    qq.leave(s['id'] as String, bid);
    return jsonOk({'ok': true, 'message': 'You left the line. No points lost.'});
  });

  r.post('/api/booths/<bid>/drop', (Request req, String bid) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    return jsonOk(qq.drop(s['id'] as String, bid,
        resumeId: j['resume_id'] as String? ?? '', note: j['note'] as String?, token: j['t'] as String?));
  });

  r.post('/api/booths/<bid>/note', (Request req, String bid) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    return jsonOk({'job_id': qq.jobs.dropNote(s['id'] as String, bid, j['resume_id'] as String? ?? '')});
  });

  r.post('/api/booths/<bid>/pitch', (Request req, String bid) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    final v = j['variant'] as String? ?? 'default';
    if (!['default', 'more_like_me', 'shorter', 'different_project'].contains(v)) {
      throw ApiError(400, 'Unknown variant');
    }
    return jsonOk({'job_id': qq.jobs.pitch(s['id'] as String, bid, variant: v)});
  });

  r.put('/api/booths/<bid>/pitch', (Request req, String bid) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    final text = (j['pitch'] as String? ?? '').trim();
    if (text.isEmpty) throw ApiError(400, 'Pitch is empty.');
    return jsonOk(qq.editPitch(s['id'] as String, bid, text, j['question'] as String?));
  });

  r.post('/api/lint', (Request req) async {
    final j = await readJson(req);
    return jsonOk(lintText(j['text'] as String? ?? '', question: j['question'] as String?).toJson());
  });

  // ================================================================= student: identity QR, rolodex, game
  r.get('/api/me/qr', (Request req) {
    final s = requireStudent(qq, req);
    final now = qq.clock();
    return jsonOk({
      'code': qq.codes.studentCode(s['id'] as String, now),
      'seconds_left': qq.codes.secondsLeft(now),
      'friend_code': qq.codes.friendCode(s['id'] as String),
    });
  });

  // ---- business cards by number (no QR)
  r.get('/api/me/cards', (Request req) => jsonOk(qq.cardBook(requireStudent(qq, req)['id'] as String)));
  r.post('/api/me/cards/request', (Request req) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    final n = int.tryParse('${j['number']}'.replaceAll('#', '').trim());
    if (j['whose'] == 'booth') {
      final b = n == null ? null : db.one('SELECT id FROM booths WHERE number=?', [n]);
      if (b == null) throw ApiError(404, 'No booth has number ${j['number']}. Booth numbers are on the plan (1 to ${qq.booths().length}).');
      return jsonOk(qq.boothCardRequest(s['id'] as String, b['id'] as String));
    }
    if (n == null) throw ApiError(400, 'Type their card number (3 or 4 digits), or a tent number.');
    return jsonOk(qq.friendRequest(s['id'] as String, n));
  });
  r.post('/api/me/cards/<id>/<action>', (Request req, String id, String action) {
    final s = requireStudent(qq, req);
    return jsonOk(qq.respondFriend(s['id'] as String, int.parse(id), action == 'accept'));
  });
  r.post('/api/booths/<bid>/card', (Request req, String bid) {
    final s = requireStudent(qq, req);
    return jsonOk(qq.boothCardRequest(s['id'] as String, bid));
  });

  r.get('/api/me/rolodex', (Request req) => jsonOk({'items': qq.rolodex(requireStudent(qq, req)['id'] as String)}));

  r.post('/api/me/rolodex/<bid>/note', (Request req, String bid) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    if (j['wav_base64'] is String) {
      final dir = qq.cfg.resolve(p.join(qq.cfg.uploadsDir, 'audio'));
      Directory(dir).createSync(recursive: true);
      final wav = p.join(dir, '${s['id']}-$bid-${qq.clock()}.wav');
      File(wav).writeAsBytesSync(base64Decode(j['wav_base64'] as String));
      return jsonOk({'job_id': qq.jobs.rolodexVoice(s['id'] as String, bid, wav)});
    }
    final note = (j['note'] as String? ?? '').trim();
    if (note.isEmpty) throw ApiError(400, 'Note is empty.');
    qq.rolodexNote(s['id'] as String, bid, note);
    return jsonOk({'ok': true});
  });

  r.post('/api/me/rolodex/<bid>/email', (Request req, String bid) {
    final s = requireStudent(qq, req);
    return jsonOk({'job_id': qq.jobs.email(s['id'] as String, bid)});
  });

  r.post('/api/me/rolodex/<bid>/sent', (Request req, String bid) {
    final s = requireStudent(qq, req);
    qq.emailSent(s['id'] as String, bid);
    return jsonOk({'ok': true, 'message': 'Marked as sent. 15 points arrive tomorrow.'});
  });

  r.post('/api/me/rolodex/<bid>/asked', (Request req, String bid) {
    final s = requireStudent(qq, req);
    qq.askedQuestion(s['id'] as String, bid);
    return jsonOk({'ok': true});
  });

  r.get('/api/me/game', (Request req) => jsonOk(qq.game.summary(requireStudent(qq, req)['id'] as String)));
  r.post('/api/me/paperless', (Request req) {
    final s = requireStudent(qq, req);
    qq.game.setPaperless(s['id'] as String);
    return jsonOk({'ok': true});
  });
  r.get('/api/me/recap', (Request req) => jsonOk(qq.game.recap(requireStudent(qq, req)['id'] as String)));
  r.get('/api/me/leaderboard', (Request req) => jsonOk(qq.game.leaderboard(requireStudent(qq, req)['id'] as String)));
  r.post('/api/me/friends', (Request req) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    return jsonOk(qq.addFriend(s['id'] as String, (j['code'] as String? ?? '').trim()));
  });

  r.get('/api/me/fairplay', (Request req) => jsonOk(qq.fairPlayStatus(requireStudent(qq, req)['id'] as String)));
  r.post('/api/me/fairplay/<bid>', (Request req, String bid) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    qq.setFairPlayPref(s['id'] as String, bid, j['excluded'] == true);
    return jsonOk(qq.fairPlayStatus(s['id'] as String));
  });

  r.get('/api/me/receipts', (Request req) => jsonOk({'items': qq.receipts(requireStudent(qq, req)['id'] as String)}));

  r.post('/api/me/access', (Request req) async {
    final s = requireStudent(qq, req);
    final j = await readJson(req);
    return jsonOk(qq.accessRequest(s['id'] as String, j['booth_id'] as String?, j['need'] as String? ?? ''));
  });

  // ================================================================= recruiter
  r.post('/api/recruiter/login', (Request req) async {
    final j = await readJson(req);
    final email = (j['email'] as String? ?? '').trim().toLowerCase();
    final b = db.one('SELECT * FROM booths WHERE lower(recruiter_email)=?', [email]);
    if (b == null || !checkPassword(j['password'] as String? ?? '', b['recruiter_password'] as String?)) {
      throw ApiError(401, 'Email or password is wrong.');
    }
    return jsonOk({'booth_id': b['id'], 'key': b['booth_key'], 'name': b['recruiter_name'], 'company': b['name'], 'number': b['recruiter_number']});
  });

  r.get('/api/recruiter/<bid>', (Request req, String bid) {
    qq.boothByKey(bid, boothKey(req));
    return jsonOk({...qq.recruiterView(bid), 'card_requests': qq.boothRequests(bid)});
  });

  /// Recruiter edits their card and booth details. Changing the sign-in email
  /// or password requires the current password.
  r.post('/api/recruiter/<bid>/profile', (Request req, String bid) async {
    final b = qq.boothByKey(bid, boothKey(req));
    final j = await readJson(req);
    String? str(String k) => (j[k] as String?)?.trim();
    final upd = <String, Object?>{};
    if (str('name')?.isNotEmpty == true) upd['recruiter_name'] = str('name');
    if (j.containsKey('title')) upd['recruiter_title'] = str('title');
    if (str('company')?.isNotEmpty == true && str('company') != b['name']) {
      if (db.one('SELECT 1 FROM booths WHERE lower(name)=? AND id<>?', [str('company')!.toLowerCase(), bid]) != null) {
        throw ApiError(409, 'Another booth already uses that company name.');
      }
      upd['name'] = str('company');
    }
    if (j.containsKey('about')) {
      upd['about'] = str('about');
      upd['tagline'] = str('about')!.isEmpty ? 'Hiring at the fair' : str('about');
    }
    if (str('role')?.isNotEmpty == true) {
      final roles = (jd(b['roles_json']) as List).cast<Map<String, dynamic>>();
      final first = roles.isEmpty ? <String, dynamic>{'desc': '', 'skills': []} : roles.first;
      roles.isEmpty ? roles.add({...first, 'title': str('role')}) : roles[0] = {...first, 'title': str('role')};
      upd['roles_json'] = je(roles);
    }
    if (['yes', 'no', 'unknown'].contains(j['sponsors'])) upd['sponsors'] = j['sponsors'];
    if (j.containsKey('card_email')) {
      final ce = str('card_email')!.toLowerCase();
      if (ce.isNotEmpty && !ce.contains('@')) throw ApiError(400, 'The card email does not look right.');
      upd['contact_email'] = ce;
    }
    final newEmail = str('email')?.toLowerCase();
    final newPass = j['new_password'] as String?;
    final changingLogin = (newEmail != null && newEmail.isNotEmpty && newEmail != (b['recruiter_email'] as String?)?.toLowerCase()) ||
        (newPass != null && newPass.isNotEmpty);
    if (changingLogin) {
      if (!checkPassword(j['current_password'] as String? ?? '', b['recruiter_password'] as String?)) {
        throw ApiError(403, 'Enter your current password to change your sign-in email or password.');
      }
      if (newEmail != null && newEmail.isNotEmpty && newEmail != (b['recruiter_email'] as String?)?.toLowerCase()) {
        if (!newEmail.contains('@')) throw ApiError(400, 'That email does not look right.');
        if (db.one('SELECT 1 FROM booths WHERE lower(recruiter_email)=? AND id<>?', [newEmail, bid]) != null) {
          throw ApiError(409, 'Another recruiter already uses that email.');
        }
        upd['recruiter_email'] = newEmail;
      }
      if (newPass != null && newPass.isNotEmpty) {
        if (newPass.length < 4) throw ApiError(400, 'New password needs at least 4 characters.');
        upd['recruiter_password'] = hashPassword(newPass);
      }
    }
    if (upd.isNotEmpty) {
      db.exec('UPDATE booths SET ${upd.keys.map((k) => '$k=?').join(', ')} WHERE id=?', [...upd.values, bid]);
      qq.changed(['booth:$bid', 'fair', 'organizer']);
    }
    final nb = qq.booth(bid);
    return jsonOk({
      'message': changingLogin ? 'Saved. Use your new sign-in details next time.' : 'Saved.',
      'card': qq.recruiterCard(nb),
      'about': nb['about'],
      'role': ((jd(nb['roles_json']) as List).firstOrNull as Map?)?['title'],
      'sponsors': nb['sponsors'],
    });
  });

  r.get('/api/recruiter/<bid>/cards', (Request req, String bid) {
    qq.boothByKey(bid, boothKey(req));
    return jsonOk(qq.recruiterCardBook(bid));
  });
  r.post('/api/recruiter/<bid>/cards/share', (Request req, String bid) async {
    qq.boothByKey(bid, boothKey(req));
    final j = await readJson(req);
    final n = int.tryParse('${j['number']}'.replaceAll('#', '').trim());
    if (n == null) throw ApiError(400, 'Type a card number (3 or 4 digits).');
    return jsonOk(qq.recruiterShare(bid, n, group: j['group'] == true));
  });
  r.post('/api/recruiter/<bid>/peers/<id>/<action>', (Request req, String bid, String id, String action) {
    qq.boothByKey(bid, boothKey(req));
    return jsonOk(qq.respondPeer(bid, int.parse(id), action == 'accept'));
  });
  r.get('/api/me/route', (Request req) => jsonOk(qq.route(requireStudent(qq, req)['id'] as String)));

  r.post('/api/recruiter/<bid>/requests/<id>/<action>', (Request req, String bid, String id, String action) async {
    qq.boothByKey(bid, boothKey(req));
    final j = await readJson(req);
    return jsonOk(qq.respondBooth(bid, int.parse(id), action == 'accept', group: j['group'] == true));
  });

  r.post('/api/recruiter/<bid>/confirm', (Request req, String bid) async {
    // Presence verification requires the booth key. A student token is never
    // accepted here, so a student cannot verify their own conversation.
    if (studentToken(req) != null && boothKey(req) == null) {
      throw ApiError(403, 'Conversations can only be confirmed from the recruiter device.');
    }
    qq.boothByKey(bid, boothKey(req));
    final j = await readJson(req);
    return jsonOk(qq.confirm(bid,
        code: j['code'] as String?,
        studentId: j['student_id'] as String?,
        number: int.tryParse('${j['number'] ?? ''}'.replaceAll('#', '').trim()),
        group: j['group'] == true,
        pile: j['pile'] as String?,
        memory: (j['memory'] as String?)?.trim().isEmpty == true ? null : j['memory'] as String?));
  });

  r.post('/api/recruiter/<bid>/mark/<sid>', (Request req, String bid, String sid) async {
    qq.boothByKey(bid, boothKey(req));
    final j = await readJson(req);
    qq.mark(bid, sid,
        stars: numOrNull(j['stars']),
        privateNote: j['private_note'] as String?,
        pile: j['pile'] as String?,
        memory: j['memory_note'] as String?,
        manualRank: numOrNull(j['manual_rank']),
        tags: (j['tags'] as List?)?.map((e) => '$e').toList(),
        clearPile: j['clear_pile'] == true,
        clearStars: j['clear_stars'] == true);
    return jsonOk({'ok': true});
  });

  r.post('/api/recruiter/<bid>/order', (Request req, String bid) async {
    qq.boothByKey(bid, boothKey(req));
    final j = await readJson(req);
    final ids = ((j['student_ids'] as List?) ?? const []).cast<String>();
    for (var i = 0; i < ids.length; i++) {
      qq.mark(bid, ids[i], manualRank: i.toDouble());
    }
    return jsonOk({'ok': true});
  });

  r.post('/api/recruiter/<bid>/piles', (Request req, String bid) async {
    qq.boothByKey(bid, boothKey(req));
    final j = await readJson(req);
    final piles = ((j['piles'] as List?) ?? const []).map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
    if (piles.length < 2 || piles.length > 6) throw ApiError(400, '2 to 6 piles.');
    final old = (jd(qq.booth(bid)['piles_json']) as List).cast<String>();
    db.tx(() {
      for (var i = 0; i < old.length && i < piles.length; i++) {
        if (old[i] != piles[i]) {
          db.exec('UPDATE recruiter_marks SET pile=? WHERE booth_id=? AND pile=?', [piles[i], bid, old[i]]);
        }
      }
      db.exec('UPDATE booths SET piles_json=? WHERE id=?', [je(piles), bid]);
    });
    qq.changed(['booth:$bid']);
    return jsonOk({'piles': piles});
  });

  r.post('/api/recruiter/<bid>/close', (Request req, String bid) {
    qq.boothByKey(bid, boothKey(req));
    final n = qq.closeBooth(bid, reason: 'recruiter left');
    return jsonOk({'credited': n, 'message': '$n students in line moved to your inbox under "Waited for you".'});
  });

  r.post('/api/recruiter/<bid>/reopen', (Request req, String bid) {
    qq.boothByKey(bid, boothKey(req));
    qq.reopenBooth(bid);
    return jsonOk({'ok': true});
  });

  r.get('/api/recruiter/<bid>/resume/<sid>', (Request req, String bid, String sid) {
    qq.boothByKey(bid, boothKey(req));
    final rid = req.url.queryParameters['rid'];
    final res = qq.resume(rid) ??
        qq.resume(qq.fit(sid, bid)?['resume_id'] as String?) ??
        (qq.resumes(sid).isEmpty ? null : qq.resumes(sid).first);
    if (res == null || res['student_id'] != sid) throw ApiError(404, 'No resume');
    final blind = req.url.queryParameters['blind'] == '1';
    return jsonOk({
      'label': res['label'],
      'text': blind ? res['blind_text'] : res['text'],
      'blind': blind,
      'summary': jd(db.one('SELECT json FROM summaries WHERE booth_id=? AND student_id=? AND resume_id=?', [bid, sid, res['id']])?['json']),
    });
  });

  r.get('/api/recruiter/<bid>/resume/<sid>/pdf', (Request req, String bid, String sid) {
    qq.boothByKey(bid, boothKey(req));
    final res = qq.resume(req.url.queryParameters['rid']);
    if (res == null || res['student_id'] != sid || res['pdf_path'] == null) throw ApiError(404, 'No PDF');
    final f = File(res['pdf_path'] as String);
    if (!f.existsSync()) throw ApiError(404, 'PDF missing');
    return Response.ok(f.readAsBytesSync(), headers: {
      'content-type': 'application/pdf',
      'content-disposition': 'inline; filename="${res['filename'] ?? 'resume.pdf'}"',
    });
  });

  List<Map<String, Object?>> filtered(String bid, Map<String, String> q) {
    final v = qq.recruiterView(bid);
    final pile = q['pile'];
    final piles = pile == null || pile.isEmpty ? null : pile.split(',');
    final minFit = double.tryParse(q['min_fit'] ?? '');
    final minStars = double.tryParse(q['min_stars'] ?? '');
    final section = q['section'];
    final out = <Map<String, Object?>>[];
    for (final s in v['sections'] as List) {
      if (section != null && section.isNotEmpty && s['key'] != section) continue;
      for (final c in (s['items'] as List).cast<Map<String, Object?>>()) {
        if (piles != null && !piles.contains(c['pile'])) continue;
        if (minFit != null && (c['fit'] as double) < minFit) continue;
        if (minStars != null && ((c['stars'] as num?) ?? 0) <= minStars) continue;
        out.add(c);
      }
    }
    return out;
  }

  String csvOf(List<Map<String, Object?>> rows, Row booth) {
    String esc(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""').replaceAll('\n', ' ')}"';
    String t(Object? ms) => ms == null ? '' : DateTime.fromMillisecondsSinceEpoch(ms as int).toLocal().toIso8601String().substring(0, 16);
    final b = StringBuffer();
    b.writeln('# ${booth['name']} shortlist. ${qq.settings().formula} Stars and piles are private and not part of Score.');
    b.writeln('rank,section,name,email,major,fit,effort,score,waited_min,pile,tags,stars,memory_note,private_note,resume,met_at,arrival_at_info_only,reason,note');
    for (final c in rows) {
      final s = c['student'] as Map;
      b.writeln([
        c['rank'], c['section'], esc(s['name']), esc(s['email']), esc(s['major']), c['fit'], c['effort'], c['score'],
        c['waited_min'], esc(c['pile']), esc(((c['tags'] as List?) ?? const []).join('; ')), c['stars'] ?? '', esc(c['memory_note']), esc(c['private_note']),
        esc(c['resume_label']), t(c['met_at']), t(c['arrival_at']), esc(c['reason']), esc(c['note']),
      ].join(','));
    }
    return b.toString();
  }

  r.get('/api/recruiter/<bid>/export.csv', (Request req, String bid) {
    final b = qq.boothByKey(bid, boothKey(req));
    final rows = filtered(bid, req.url.queryParameters);
    return Response.ok(csvOf(rows, b), headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="${bid}_shortlist.csv"',
    });
  });

  r.get('/api/recruiter/<bid>/export.zip', (Request req, String bid) {
    final b = qq.boothByKey(bid, boothKey(req));
    final rows = filtered(bid, req.url.queryParameters);
    final arch = Archive();
    final csv = utf8.encode(csvOf(rows, b));
    arch.addFile(ArchiveFile('shortlist.csv', csv.length, csv));
    for (final c in rows) {
      final res = qq.resume(c['resume_id'] as String?);
      if (res == null) continue;
      final name = '${(c['rank'] as int).toString().padLeft(3, '0')}_${((c['student'] as Map)['name'] as String).replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_${(res['label'] as String).replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')}';
      final path = res['pdf_path'] as String?;
      if (path != null && File(path).existsSync()) {
        final bytes = File(path).readAsBytesSync();
        arch.addFile(ArchiveFile('$name.pdf', bytes.length, bytes));
      } else {
        final bytes = utf8.encode(res['text'] as String);
        arch.addFile(ArchiveFile('$name.txt', bytes.length, bytes));
      }
    }
    final zip = ZipEncoder().encode(arch)!;
    return Response.ok(zip, headers: {
      'content-type': 'application/zip',
      'content-disposition': 'attachment; filename="${bid}_shortlist.zip"',
    });
  });

  // ================================================================= organizer
  r.get('/api/organizer', (Request req) {
    qq.requireOrganizer(orgKey(req));
    return jsonOk(qq.organizerView());
  });

  r.post('/api/organizer/settings', (Request req) async {
    qq.requireOrganizer(orgKey(req));
    final j = await readJson(req);
    qq.updateSettings(wFit: numOrNull(j['w_fit']), wEffort: numOrNull(j['w_effort']), capMin: (j['cap_min'] as num?)?.toInt());
    if (j['ai_live'] != null) {
      db.setMeta('ai_live', j['ai_live'] == true ? '1' : '0');
    }
    if (j['demo_mode'] != null) {
      db.setMeta('demo_mode', j['demo_mode'] == true ? '1' : '0');
    }
    qq.changed(['fair', 'organizer']);
    return jsonOk(qq.organizerView());
  });

  r.post('/api/organizer/close', (Request req) {
    qq.requireOrganizer(orgKey(req));
    return jsonOk(qq.closeFair());
  });

  r.post('/api/organizer/simulate', (Request req) async {
    qq.requireOrganizer(orgKey(req));
    final j = await readJson(req);
    if (j['on'] == true) {
      qq.startSimulation();
    } else {
      qq.stopSimulation();
    }
    return jsonOk({'simulating': qq.simulating});
  });

  r.post('/api/organizer/reset', (Request req) async {
    qq.requireOrganizer(orgKey(req));
    await qq.jobs.drain();
    await Seeder(qq).run();
    return jsonOk({'ok': true, 'message': 'Demo reset to seed.'});
  });

  r.get('/api/organizer/audit', (Request req) {
    qq.requireOrganizer(orgKey(req));
    final a = qq.audit()..remove('rows');
    return jsonOk(a);
  });

  r.get('/api/organizer/audit.csv', (Request req) {
    qq.requireOrganizer(orgKey(req));
    return Response.ok(qq.auditCsv(), headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="fairness_audit.csv"',
    });
  });

  r.post('/api/organizer/access/<id>/resolve', (Request req, String id) {
    qq.requireOrganizer(orgKey(req));
    qq.resolveAccess(int.parse(id));
    return jsonOk({'ok': true});
  });

  /// Accessibility exception: staff confirm a conversation held at the
  /// accessibility desk or by video.
  r.post('/api/organizer/staff-confirm', (Request req) async {
    qq.requireOrganizer(orgKey(req));
    final j = await readJson(req);
    return jsonOk(qq.confirm(j['booth_id'] as String, studentId: j['student_id'] as String?, confirmedBy: 'staff'));
  });

  r.get('/api/organizer/students', (Request req) {
    qq.requireOrganizer(orgKey(req));
    final q = (req.url.queryParameters['q'] ?? '').toLowerCase();
    return jsonOk({
      'items': db
          .all('SELECT id, name, major, avatar, accommodation, checked_in_at, is_sim FROM students WHERE lower(name) LIKE ? ORDER BY is_sim, name LIMIT 30',
              ['%$q%'])
          .toList()
    });
  });

  return r;
}
