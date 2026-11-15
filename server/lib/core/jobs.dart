import 'dart:async';
import 'dart:io';

import '../ai/ai_service.dart';
import '../ai/transcribe.dart';
import '../db/db.dart';
import '../util/codes.dart';
import 'qq.dart';

class JobCtx {
  final Jobs jobs;
  final String id;
  int total;
  JobCtx(this.jobs, this.id, this.total);
  void report(int progress, String message, {int? total}) {
    if (total != null) this.total = total;
    jobs._update(id, status: 'running', progress: progress, message: message, total: this.total);
  }
}

/// AI work runs as background jobs so the UI never blocks. Jobs run one at a
/// time: the host laptop has one model and we want each call at full speed.
class Jobs {
  final QQ qq;
  Future<void> _chain = Future.value();
  Jobs(this.qq);

  Db get db => qq.db;

  Map<String, Object?>? get(String id) {
    final r = db.one('SELECT * FROM ai_jobs WHERE id=?', [id]);
    if (r == null) return null;
    return {
      'id': r['id'],
      'kind': r['kind'],
      'status': r['status'],
      'progress': r['progress'],
      'total': r['total'],
      'message': r['message'],
      'result': jd(r['result_json']),
    };
  }

  void _update(String id, {String? status, int? progress, int? total, String? message, Object? result}) {
    final cur = db.one('SELECT * FROM ai_jobs WHERE id=?', [id]);
    if (cur == null) return;
    db.exec('UPDATE ai_jobs SET status=?, progress=?, total=?, message=?, result_json=?, updated_at=? WHERE id=?', [
      status ?? cur['status'],
      progress ?? cur['progress'],
      total ?? cur['total'],
      message ?? cur['message'],
      result == null ? cur['result_json'] : je(result),
      qq.clock(),
      id,
    ]);
    qq.changed(['job:$id', if (cur['student_id'] != null) 'student:${cur['student_id']}']);
  }

  String start(String kind,
      {String? studentId,
      String? boothId,
      int total = 1,
      String message = 'Queued',
      required Future<Object?> Function(JobCtx j) run}) {
    final id = Codes.randomToken(9);
    final now = qq.clock();
    db.insert('ai_jobs', {
      'id': id,
      'kind': kind,
      'student_id': studentId,
      'booth_id': boothId,
      'status': 'queued',
      'progress': 0,
      'total': total,
      'message': message,
      'created_at': now,
      'updated_at': now,
    });
    final ctx = JobCtx(this, id, total);
    _chain = _chain.then((_) async {
      try {
        _update(id, status: 'running');
        final res = await run(ctx);
        _update(id, status: 'done', progress: ctx.total, result: res ?? const {}, message: 'Done');
      } catch (e) {
        final msg = e is AiFailure || e is ApiError ? e.toString() : 'Something went wrong: $e';
        _update(id, status: 'error', message: msg);
      }
    });
    return id;
  }

  /// Latest job of a kind for a student (so a reloaded page can resume).
  Map<String, Object?>? latest(String sid, String kind, {String? boothId}) {
    final r = db.one(
        'SELECT id FROM ai_jobs WHERE student_id=? AND kind=? ${boothId == null ? '' : 'AND booth_id=?'} '
        'ORDER BY created_at DESC LIMIT 1',
        [sid, kind, if (boothId != null) boothId]);
    return r == null ? null : get(r['id'] as String);
  }

  // ------------------------------------------------------------ domain jobs
  String onboard(String sid) {
    final rs = qq.resumes(sid);
    final hasVoice = db.one('SELECT 1 FROM voice_profiles WHERE student_id=? AND profile_json IS NOT NULL', [sid]) != null;
    final nBooths = qq.booths().length;
    final total = rs.length + nBooths;
    return start('onboard', studentId: sid, total: total, message: 'Queued', run: (j) async {
      var i = 0;
      for (final r in rs) {
        i++;
        j.report(i - 1, 'Reading your resumes: $i of ${rs.length}');
        if (r['parsed_json'] == null) {
          final p = await qq.ai.parseResume(ResumeCtx(
              id: r['id'] as String, label: r['label'] as String, blindText: r['blind_text'] as String));
          db.exec('UPDATE resumes SET parsed_json=? WHERE id=?', [je(p), r['id']]);
        }
      }
      await _plan(sid, j, offset: rs.length);
      return {'voice': hasVoice};
    });
  }

  Future<void> _plan(String sid, JobCtx j, {int offset = 0}) async {
    final bs = qq.booths();
    var k = 0;
    for (final b in bs) {
      k++;
      j.report(offset + k - 1, 'Scoring booths for fit: $k of ${bs.length}');
      await qq.computeFit(sid, b['id'] as String);
      qq.changed(['student:$sid']);
    }
    qq.game.chooseQuests(sid, force: true);
  }

  String plan(String sid) {
    final n = qq.booths().length;
    return start('plan', studentId: sid, total: n, run: (j) async {
      await _plan(sid, j);
      return null;
    });
  }

  String voice(String sid, {String? wavPath, String? transcript, List<String> answers = const []}) {
    return start('voice', studentId: sid, total: 2, message: 'Queued', run: (j) async {
      var t = transcript ?? '';
      if (wavPath != null) {
        j.report(0, 'Transcribing your recording on this laptop');
        try {
          t = await qq.whisper.transcribe(wavPath);
        } on AudioProblem catch (e) {
          throw ApiError(400, e.message);
        } catch (e) {
          throw ApiError(503, 'Speech-to-text failed on the host laptop ($e). Type your answer instead.');
        } finally {
          try {
            File(wavPath).deleteSync();
          } catch (_) {}
        }
      }
      final words = '$t ${answers.join(' ')}'.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      if (words < 8) {
        throw ApiError(400, t.trim().isEmpty
            ? 'No speech was recognized. Try again, or type it.'
            : 'Only caught "${t.trim()}". Say a few sentences (about 20 to 30 seconds), or type it.');
      }
      j.report(1, 'Learning how you talk');
      final p = await qq.ai.voiceProfile(t, answers);
      final cur = db.one('SELECT edits_json FROM voice_profiles WHERE student_id=?', [sid]);
      db.upsert('voice_profiles', {
        'student_id': sid,
        'transcript': t,
        'answers_json': je(answers),
        'profile_json': je(p),
        'edits_json': cur?['edits_json'] ?? '[]',
        'updated_at': qq.clock(),
      }, ['student_id']);
      db.exec('UPDATE students SET voice_skipped=0 WHERE id=?', [sid]);
      db.exec('DELETE FROM pitches WHERE student_id=?', [sid]);
      return {'transcript': t, 'profile': p};
    });
  }

  String pitch(String sid, String boothId, {String variant = 'default'}) {
    return start('pitch', studentId: sid, boothId: boothId, total: 4, message: 'Queued', run: (j) async {
      final b = qq.booth(boothId);
      final ctx = qq.studentCtx(sid);
      final f = qq.fit(sid, boothId);
      final label = qq.resume(f?['resume_id'] as String?)?['label'] as String?;
      final cur = qq.pitchFor(sid, boothId);
      j.report(0, qq.aiLive
          ? 'Picking the facts that matter for ${b['name']}'
          : 'Loading your pitch for ${b['name']}');
      qq.ai.live.onStep = (m) => j.report(_stepIdx(m), m);
      try {
        final p = await qq.ai.pitch(ctx, qq.boothCtx(b),
            variant: variant, resumeLabel: label, excludeProject: cur?['project'] as String?);
        qq.savePitch(sid, boothId, p);
      } finally {
        qq.ai.live.onStep = null;
      }
      qq.changed(['student:$sid']);
      return qq.pitchFor(sid, boothId);
    });
  }

  static int _stepIdx(String m) => m.startsWith('Draft')
      ? 1
      : (m.startsWith('Critic') ? 2 : (m.startsWith('Rewrit') ? 3 : 0));

  String dropNote(String sid, String boothId, String resumeId) {
    return start('note', studentId: sid, boothId: boothId, message: 'Writing a 2-line note in your voice', run: (j) async {
      final ctx = qq.studentCtx(sid);
      final r = ctx.resumes.firstWhere((x) => x.id == resumeId, orElse: () => ctx.defaultResume);
      return qq.ai.dropNote(ctx, qq.boothCtx(qq.booth(boothId)), r);
    });
  }

  String email(String sid, String boothId) {
    return start('email', studentId: sid, boothId: boothId, message: 'Drafting your follow-up', run: (j) async {
      final row = db.one('SELECT * FROM rolodex WHERE student_id=? AND booth_id=?', [sid, boothId]);
      if (row == null) throw ApiError(404, 'Not in your rolodex.');
      final b = qq.booth(boothId);
      final ctx = qq.studentCtx(sid);
      final ex = db.one('SELECT resume_id FROM exchanges WHERE student_id=? AND booth_id=?', [sid, boothId]);
      final r = ctx.resumes.where((x) => x.id == ex?['resume_id']).firstOrNull;
      final e = await qq.ai.followUpEmail(ctx, qq.boothCtx(b),
          note: (row['note'] as String?) ?? '', recruiterName: (b['recruiter_name'] ?? 'there') as String, resume: r);
      db.exec('UPDATE rolodex SET email_json=? WHERE id=?', [je(e), row['id']]);
      return e;
    });
  }

  String rolodexVoice(String sid, String boothId, String wavPath) {
    return start('rolodex_voice', studentId: sid, boothId: boothId, total: 2, run: (j) async {
      j.report(0, 'Transcribing your note on this laptop');
      String t;
      try {
        t = await qq.whisper.transcribe(wavPath);
      } on AudioProblem catch (e) {
        throw ApiError(400, e.message);
      } catch (e) {
        final s = qq.student(sid);
        final demo = qq.ai.cached.get('transcript:${s['persona']}:$boothId') ??
            qq.ai.cached.get('transcript:${s['persona']}:any');
        if (qq.demoMode && demo != null) {
          t = demo['text'] as String;
        } else {
          throw ApiError(503, 'Speech-to-text is not set up on the host laptop. Type the note instead.');
        }
      } finally {
        try {
          File(wavPath).deleteSync();
        } catch (_) {}
      }
      qq.rolodexNote(sid, boothId, t);
      return {'note': t};
    });
  }

  /// Recruiter-facing summary; generated once per (booth, student, resume).
  void ensureSummary(String boothId, String sid, String resumeId) {
    if (db.one('SELECT 1 FROM summaries WHERE booth_id=? AND student_id=? AND resume_id=?', [boothId, sid, resumeId]) != null) {
      return;
    }
    if (qq.student(sid)['is_sim'] == 1) {
      qq.offlineSummary(boothId, sid, resumeId);
      return;
    }
    start('summary', studentId: null, boothId: boothId, run: (j) async {
      final ctx = qq.studentCtx(sid);
      final r = ctx.resumes.firstWhere((x) => x.id == resumeId, orElse: () => ctx.defaultResume);
      final s = await qq.ai.recruiterSummary(ctx, qq.boothCtx(qq.booth(boothId)), r);
      db.upsert('summaries', {
        'booth_id': boothId,
        'student_id': sid,
        'resume_id': resumeId,
        'json': je(s),
        'updated_at': qq.clock(),
      }, ['booth_id', 'student_id', 'resume_id']);
      qq.changed(['booth:$boothId']);
      return null;
    });
  }

  /// Wait for all queued jobs (tests and seeding).
  Future<void> drain() async {
    Future<void> c;
    do {
      c = _chain;
      await c;
    } while (!identical(c, _chain));
  }
}
