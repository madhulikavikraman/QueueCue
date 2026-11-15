import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../core/qq.dart';
import '../db/db.dart';
import '../fairness/fairness_engine.dart';
import '../util/blind.dart';
import '../util/codes.dart';
import '../util/mini_pdf.dart';

const avatars = ['fox', 'owl', 'bear', 'cat', 'frog', 'panda', 'koala', 'tiger', 'otter', 'bunny'];

/// Seeds one fair, 12 booths, 3 demo personas and a crowd of simulated
/// students with lines, conversations and drops spread over the morning.
class Seeder {
  final QQ qq;
  final Random rnd;
  Seeder(this.qq, {int seed = 7}) : rnd = Random(seed);
  Db get db => qq.db;

  Map<String, dynamic> loadSeed() => jsonDecode(
      File(p.join(qq.cfg.seedDir, 'fair_seed.json')).readAsStringSync()) as Map<String, dynamic>;

  static String demoToken(String persona) => 'demo-$persona';
  static String boothKey(String boothId) => 'bk-$boothId';

  Future<void> run({int sims = 110, bool withActivity = true}) async {
    qq.stopSimulation();
    final data = loadSeed();
    final now = qq.clock();
    final startsAt = now - 4 * 3600 * 1000 + 5 * 60 * 1000; // ~4 h in
    final f = data['fair'] as Map<String, dynamic>;
    final seed = Codes.randomToken(24);
    final demo = qq.demoMode;
    final aiLive = qq.aiLive;
    db.wipe();
    db.setMeta('demo_mode', demo ? '1' : '0');
    db.setMeta('ai_live', aiLive ? '1' : '0');
    if (db.meta('server_secret') == null) db.setMeta('server_secret', qq.codes.secret);
    db.insert('fairs', {
      'id': f['id'],
      'name': f['name'],
      'venue': f['venue'],
      'starts_at': startsAt,
      'ends_at': startsAt + (f['duration_hours'] as int) * 3600 * 1000,
      'status': 'open',
      'seed': seed,
      'seed_hash': FairnessEngine.sha256Hex(seed),
      'floor_w': f['floor_w'],
      'floor_h': f['floor_h'],
    });
    for (final b in (data['booths'] as List).cast<Map<String, dynamic>>()) {
      final rec = b['recruiter'] as Map<String, dynamic>;
      db.insert('booths', {
        'id': b['id'],
        'fair_id': f['id'],
        'number': b['number'],
        'name': b['name'],
        'tagline': b['tagline'],
        'category': b['category'],
        'about': b['about'],
        'roles_json': je(b['roles']),
        'sponsors': b['sponsors'],
        'majors_json': je(b['majors']),
        'partial_majors_json': je(b['partial_majors'] ?? []),
        'citizenship_required': b['citizenship_required'] == true ? 1 : 0,
        'x': b['x'],
        'y': b['y'],
        'booth_key': boothKey(b['id'] as String),
        'recruiter_name': rec['name'],
        'recruiter_email': rec['email'],
        'recruiter_password': rec['password'],
        'recruiter_title': 'Campus recruiter',
        'recruiter_number': 100 + (b['number'] as int) * 61 % 900,
        'default_service_min': b['default_service_min'] ?? 4,
      });
    }
    // ---- personas
    final up = qq.cfg.resolve(qq.cfg.uploadsDir);
    Directory(up).createSync(recursive: true);
    for (final ps in (data['personas'] as List).cast<Map<String, dynamic>>()) {
      final id = 'stu-${ps['persona']}';
      db.insert('students', {
        'id': id,
        'fair_id': f['id'],
        'token': demoToken(ps['persona'] as String),
        'number': ps['number'],
        'password_hash': 'hogwarts', // demo password for the seeded students
        'interests': ps['interests'],
        'bio': ps['bio'],
        'name': ps['name'],
        'email': ps['email'],
        'phone': ps['phone'],
        'linkedin': ps['linkedin'],
        'major': ps['major'],
        'degree': ps['degree'],
        'grad_year': ps['grad_year'],
        'work_auth': ps['work_auth'],
        'avatar': ps['avatar'],
        'persona': ps['persona'],
        'leaderboard_opt_in': 1,
        'onboarded': 1,
        // Seed story: Viktor and Hermione arrived in the first hour; Percy later.
        'checked_in_at': ps['persona'] == 'percy' ? null : startsAt + (ps['persona'] == 'viktor' ? 35 : 20) * 60 * 1000,
        'created_at': startsAt,
      });
      var i = 0;
      for (final r in (ps['resumes'] as List).cast<Map<String, dynamic>>()) {
        i++;
        final rid = 'r-${ps['persona']}-$i';
        final pdf = p.join(up, '$rid.pdf');
        File(pdf).writeAsBytesSync(textToPdf('${ps['name']} - ${r['label']}', r['text'] as String));
        db.insert('resumes', {
          'id': rid,
          'student_id': id,
          'label': r['label'],
          'filename': '${(ps['name'] as String).replaceAll(' ', '_')}_${(r['label'] as String).replaceAll('/', '-')}.pdf',
          'pdf_path': pdf,
          'text': r['text'],
          'blind_text': blindResume(r['text'] as String, nameTokens: (ps['name'] as String).split(' ')),
          'is_default': r['is_default'] == true ? 1 : 0,
          'created_at': startsAt + i,
        });
      }
      final v = ps['voice'] as Map<String, dynamic>;
      db.insert('voice_profiles', {
        'student_id': id,
        'transcript': v['transcript'],
        'answers_json': je(v['answers']),
        'profile_json': je({...(v['profile'] as Map), 'source': 'seed'}),
        'edits_json': '[]',
        'updated_at': startsAt,
      });
    }
    final personaIds = [for (final ps in data['personas'] as List) 'stu-${ps['persona']}'];
    for (final a in personaIds) {
      for (final b in personaIds) {
        if (a != b) db.insert('friends', {'student_id': a, 'friend_id': b, 'created_at': startsAt});
      }
    }
    for (final pid in personaIds) {
      for (final b in qq.booths()) {
        await qq.computeFit(pid, b['id'] as String);
      }
      qq.game.chooseQuests(pid, force: true);
      qq.game.onCheckIn(pid); // Early Bird when checked in during the first hour
    }

    // ---- simulated crowd
    final names = (data['sim_first_names'] as List).cast<String>();
    final profiles = (data['sim_profiles'] as List).cast<Map<String, dynamic>>();
    final simIds = <String>[];
    for (var k = 0; k < sims; k++) {
      final id = 'sim-$k';
      final pr = profiles[rnd.nextInt(profiles.length)];
      final auth = _pickAuth();
      final name = '${names[k % names.length]} ${String.fromCharCode(65 + rnd.nextInt(26))}.';
      db.insert('students', {
        'id': id,
        'fair_id': f['id'],
        'token': 'sim-token-$k-${Codes.randomToken(6)}',
        'number': _simNumber(),
        'name': name,
        'major': pr['major'],
        'degree': rnd.nextBool() ? 'BS' : 'MS',
        'grad_year': 2026 + rnd.nextInt(2),
        'work_auth': auth,
        'avatar': avatars[rnd.nextInt(avatars.length)],
        'is_sim': 1,
        'leaderboard_opt_in': rnd.nextInt(3) == 0 ? 1 : 0,
        'checked_in_at': startsAt + rnd.nextInt(max(1, now - startsAt - 10 * 60 * 1000)),
        'onboarded': 1,
        'created_at': startsAt,
      });
      final skills = (pr['skills'] as List).cast<String>()..shuffle(rnd);
      final txt = _simResume(pr['major'] as String, skills);
      db.insert('resumes', {
        'id': 'r-$id',
        'student_id': id,
        'label': 'General',
        'text': txt,
        'blind_text': txt,
        'is_default': 1,
        'created_at': startsAt,
      });
      for (final b in qq.booths()) {
        await qq.computeFit(id, b['id'] as String);
      }
      simIds.add(id);
    }
    // Two sim friends for each persona so the friends leaderboard is not empty.
    for (final pid in personaIds) {
      for (final sid in simIds.take(2)) {
        db.upsert('friends', {'student_id': pid, 'friend_id': sid, 'created_at': startsAt}, ['student_id', 'friend_id']);
        db.upsert('friends', {'student_id': sid, 'friend_id': pid, 'created_at': startsAt}, ['student_id', 'friend_id']);
        db.exec('UPDATE students SET leaderboard_opt_in=1 WHERE id=?', [sid]);
      }
    }
    if (withActivity) _seedActivity(simIds, startsAt, now);
    db.setMeta('seeded_at', '$now');
    qq.changed(['fair', 'organizer', for (final b in qq.booths()) 'booth:${b['id']}', for (final pid in personaIds) 'student:$pid']);
  }

  final _used = <int>{1042, 4512, 3307};
  /// Unique 4-digit student card number.
  int _simNumber() {
    while (true) {
      final n = 1000 + rnd.nextInt(9000);
      if (_used.add(n)) return n;
    }
  }

  String _pickAuth() {
    final r = rnd.nextDouble();
    if (r < 0.66) return 'citizen';
    if (r < 0.76) return 'permanent_resident';
    if (r < 0.94) return 'f1_cpt_opt';
    return 'h1b';
  }

  String _simResume(String major, List<String> skills) {
    final s = skills.take(3).toList();
    final n = 10 + rnd.nextInt(80);
    return 'EDUCATION\n$major.\nPROJECTS\nCourse project: built a tool using ${s.join(', ')}; tested with $n users.\n'
        'Team project: ${s.first} work for a student club; cut a manual task by ${20 + rnd.nextInt(60)}%.\nSKILLS\n${skills.join(', ')}';
  }

  static const _lineSizes = {
    'northwind': 13,
    'lumen': 6,
    'halcyon': 2,
    'copperline': 3,
    'ridgeway': 8,
    'parcelpilot': 1,
    'bayside': 4,
    'orbital': 1,
    'kestrel': 9,
    'meridian': 7,
    'gridwise': 2,
    'stackline': 5,
  };

  void _seedActivity(List<String> simIds, int startsAt, int now) {
    final pool = [...simIds]..shuffle(rnd);
    var next = 0;
    String take() => pool[next++ % pool.length];
    final booths = qq.booths();
    final piles = ['Standout', 'Strong', 'Maybe', 'Not now'];
    final mid = startsAt + 3 * 3600 * 1000;
    for (final b in booths) {
      final bid = b['id'] as String;
      // Past conversations with realistic service gaps.
      final nEx = bid == 'northwind' ? 24 : 4 + rnd.nextInt(8);
      final base = (b['default_service_min'] as num).toDouble() * 60;
      var t = now - 2 * 60 * 1000;
      final exRows = <Map<String, Object?>>[];
      const nwGaps = [170.0, 195.0, 180.0, 200.0, 175.0, 190.0, 185.0, 193.0];
      for (var i = 0; i < nEx; i++) {
        final gap = bid == 'northwind' && i < 8 ? nwGaps[i] : base * (0.75 + rnd.nextDouble() * 0.5);
        exRows.add({'t': t, 'gap': gap});
        t -= (gap * 1000).round() + (i % 5 == 4 ? 6 * 60 * 1000 : 0);
        if (t < startsAt + 5 * 60 * 1000) break;
      }
      for (final e in exRows) {
        final sid = take();
        final at = e['t'] as int;
        final waited = 5 + rnd.nextInt(40) + 0.0;
        db.insert('queue_entries', {
          'booth_id': bid,
          'student_id': sid,
          'joined_at': at - (waited * 60000).round(),
          'left_at': at,
          'status': 'served',
          'est_wait_at_join': waited,
        });
        final exId = db.insert('exchanges', {
          'booth_id': bid,
          'student_id': sid,
          'method': rnd.nextInt(3) == 0 ? 'met' : 'scan',
          'confirmed_by': 'recruiter',
          'service_sec': e['gap'],
          'waited_min': waited,
          'resume_id': 'r-$sid',
          'created_at': at,
        });
        db.upsert('rolodex', {'student_id': sid, 'booth_id': bid, 'exchange_id': exId, 'created_at': at},
            ['student_id', 'booth_id']);
        // Northwind shows the rating-drift notice: generous early, harsher late.
        final early = at < mid;
        final idx = exRows.indexOf(e);
        final pile = bid == 'northwind'
            ? (early ? (idx % 10 < 7 ? piles[idx % 2] : piles[2 + idx % 2]) : (idx % 10 == 0 ? piles[1] : piles[2 + idx % 2]))
            : piles[rnd.nextInt(4)];
        if (bid == 'northwind' || rnd.nextInt(5) != 0) {
          db.insert('recruiter_marks', {
            'booth_id': bid,
            'student_id': sid,
            'pile': pile,
            'stars': rnd.nextInt(4) == 0 ? null : (2 + rnd.nextInt(4)).toDouble(),
            'memory_note': rnd.nextInt(3) == 0 ? _memo() : null,
            'updated_at': at,
          });
        }
        db.insert('points', {
          'student_id': sid,
          'rule': 'conversation',
          'points': 30,
          'booth_id': bid,
          'ref': bid,
          'created_at': at,
          'award_at': at,
        });
        qq.offlineSummary(bid, sid, 'r-$sid');
      }
      if (exRows.isNotEmpty) {
        db.exec('UPDATE booths SET last_confirm_at=? WHERE id=?', [exRows.first['t'], bid]);
      }
      // Current line (strict FIFO by joined_at).
      final n = _lineSizes[bid] ?? 3;
      final waitingIds = <String>{};
      for (var i = 0; i < n; i++) {
        String? sid;
        for (var tries = 0; tries < pool.length; tries++) {
          final c = take();
          if (waitingIds.contains(c) ||
              db.one("SELECT 1 FROM queue_entries WHERE student_id=? AND status='waiting'", [c]) != null ||
              db.one('SELECT 1 FROM exchanges WHERE student_id=? AND booth_id=?', [c, bid]) != null) {
            continue;
          }
          sid = c;
          break;
        }
        if (sid == null) break; // crowd too small for this line size
        waitingIds.add(sid);
        final joined = now - ((n - i) * 3 * 60 * 1000) + rnd.nextInt(60000);
        db.insert('queue_entries', {
          'booth_id': bid,
          'student_id': sid,
          'joined_at': joined,
          'status': 'waiting',
          'est_wait_at_join': i * 3.0,
        });
      }
      // A few resume drops.
      for (var i = 0; i < 1 + rnd.nextInt(4); i++) {
        final sid = take();
        if (db.one('SELECT 1 FROM drops WHERE student_id=? AND booth_id=?', [sid, bid]) != null) continue;
        db.insert('drops', {
          'booth_id': bid,
          'student_id': sid,
          'resume_id': 'r-$sid',
          'kind': 'drop',
          'est_wait_min': 20,
          'created_at': startsAt + rnd.nextInt(now - startsAt),
        });
        qq.offlineSummary(bid, sid, 'r-$sid');
      }
    }
  }

  String _memo() => const [
        'robotics club, asked about sim-to-real',
        'built a Discord bot for course help',
        'asked about on-call for new grads',
        'TA for data structures',
        'hackathon winner, payments demo',
        'wants embedded, not web',
        'good question on eval sets',
        'transfer student, strong SQL',
      ][rnd.nextInt(8)];
}

/// "Simulate crowd": sims join lines and get served over time so lines and
/// estimates visibly move. Only sims at the FRONT are served; nobody is ever
/// skipped and real students are never moved by the simulator.
extension Simulation on QQ {
  void startSimulation() {
    if (simTimer != null) return;
    simTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      try {
        simTick();
      } catch (_) {}
    });
    changed(['organizer']);
  }

  void stopSimulation() {
    simTimer?.cancel();
    simTimer = null;
    changed(['organizer']);
  }

  void simTick() {
    if (!fairOpen) return;
    final open = booths().where((b) => b['status'] == 'open').toList();
    if (open.isEmpty) return;
    for (var k = 0; k < 2; k++) {
      final b = open[rnd.nextInt(open.length)];
      final bid = b['id'] as String;
      final w = waiting(bid);
      final target = bid == 'northwind' ? 14 : 5;
      final r = rnd.nextDouble();
      if (r < 0.5 && w.length < target + 4) {
        final sid = db.one(
            "SELECT id FROM students s WHERE is_sim=1 AND NOT EXISTS (SELECT 1 FROM queue_entries q WHERE q.student_id=s.id AND q.status='waiting') "
            'AND NOT EXISTS (SELECT 1 FROM exchanges e WHERE e.student_id=s.id AND e.booth_id=?) ORDER BY random() LIMIT 1',
            [bid])?['id'] as String?;
        if (sid == null) continue;
        db.insert('queue_entries', {
          'booth_id': bid,
          'student_id': sid,
          'joined_at': clock(),
          'status': 'waiting',
          'est_wait_at_join': WaitEstimate.of(w.length, avgServiceMin(bid)).highMin.toDouble(),
        });
        changed(['booth:$bid', 'organizer']);
      } else if (r < 0.92 && w.isNotEmpty) {
        final front = w.first;
        final s = student(front['student_id'] as String);
        final last = b['last_confirm_at'] as int?;
        if (s['is_sim'] != 1) continue; // never move a real student
        if (last != null && clock() - last < 25000) continue;
        try {
          confirm(bid, studentId: s['id'] as String, pile: ['Standout', 'Strong', 'Maybe', 'Not now'][rnd.nextInt(4)]);
        } catch (_) {}
      } else if (w.length > 2) {
        // Someone gives up and leaves (no penalty).
        final e = w[1 + rnd.nextInt(w.length - 1)];
        if (student(e['student_id'] as String)['is_sim'] == 1) {
          leave(e['student_id'] as String, bid);
        }
      }
    }
  }
}
