import 'dart:math';

import '../core/qq.dart';
import '../db/db.dart';
import '../fairness/fairness_engine.dart';

/// Fair Play points. Rewards real, quality actions; volume is capped.
/// Points NEVER influence what recruiters see or the order they see it in
/// (the fairness engine does not read this table; tests prove it).
class Rules {
  static const conversation = 30; // recruiter-verified
  static const askedQuestion = 10; // self-reported, one tap, after a verified chat
  static const dropHighFit = 8; // fit 70+
  static const dropMidFit = 4; // fit 50-69
  static const maxScoredDrops = 8;
  static const matchedResume = 3; // used the matched (non-default) resume
  static const rolodexNote = 5; // within 10 min of the conversation
  static const followUp = 15; // within 24 h, awarded the next day
  static const offBeaten = 10; // high-fit booth with a short line
  static const earlyBird = 10; // capped so latecomers are not punished

  static const levels = [
    {'name': 'Rookie', 'min': 0},
    {'name': 'Regular', 'min': 20},
    {'name': 'Networker', 'min': 60},
    {'name': 'Closer', 'min': 100},
  ];

  static const table = [
    {'rule': 'Verified conversation (recruiter scanned your card)', 'points': conversation},
    {'rule': 'Asked your pitch question (one tap after the chat)', 'points': askedQuestion},
    {'rule': 'Resume drop at a booth with fit 70+', 'points': dropHighFit},
    {'rule': 'Resume drop at fit 50 to 69', 'points': dropMidFit},
    {'rule': 'Resume drop at fit below 50 (still allowed)', 'points': 0},
    {'rule': 'Max scored drops per fair', 'points': maxScoredDrops, 'is_cap': true},
    {'rule': 'Used the matched resume (not your default)', 'points': matchedResume},
    {'rule': 'Rolodex note within 10 min of a conversation', 'points': rolodexNote},
    {'rule': 'Follow-up sent within 24 hours (awarded next day)', 'points': followUp},
    {'rule': 'Off the beaten booth: fit 80+ with under 10 min wait', 'points': offBeaten},
    {'rule': 'Early Bird: checked in during the first hour (one time)', 'points': earlyBird},
    {'rule': 'Joining and leaving a line', 'points': 0},
    {'rule': 'Minutes spent in the app', 'points': 0},
  ];
}

const questCatalog = {
  'comfort': 'Talk to one company outside your comfort zone',
  'question': 'Ask a question no one else asks (your pitch question counts)',
  'paperless': 'Go paperless: zero printed resumes',
  'followup': 'Follow up with everyone you met by tomorrow',
  'shortwait': "Visit a booth with under 10 minutes' wait and a fit above 80",
};

const badgeCatalog = {
  'first_handshake': {'name': 'First Handshake', 'desc': 'First recruiter-verified conversation'},
  'paperless': {'name': 'Paperless', 'desc': 'Zero printed resumes'},
  'early_bird': {'name': 'Early Bird', 'desc': 'Checked in during the first hour'},
  'off_beaten': {'name': 'Off the Beaten Booth', 'desc': 'High-fit booth with a short line'},
  'follow_through': {'name': 'Follow-Through', 'desc': 'Followed up with everyone you met'},
  'full_house': {'name': 'Full House', 'desc': 'All 3 side quests'},
};

class Game {
  final QQ qq;
  Game(this.qq);
  Db get db => qq.db;

  bool _award(String sid, String rule, int pts, {String? boothId, String? ref, int? awardAt}) {
    if (pts <= 0) return false;
    final now = qq.clock();
    final exists = db.one('SELECT 1 FROM points WHERE student_id=? AND rule=? AND ref=?', [sid, rule, ref ?? boothId ?? '-']);
    if (exists != null) return false;
    db.insert('points', {
      'student_id': sid,
      'rule': rule,
      'points': pts,
      'booth_id': boothId,
      'ref': ref ?? boothId ?? '-',
      'created_at': now,
      'award_at': awardAt ?? now,
    });
    return true;
  }

  int totalPoints(String sid) =>
      ((db.scalar('SELECT COALESCE(SUM(points),0) FROM points WHERE student_id=? AND award_at<=?', [sid, qq.clock()])) as num)
          .toInt();
  int pendingPoints(String sid) =>
      ((db.scalar('SELECT COALESCE(SUM(points),0) FROM points WHERE student_id=? AND award_at>?', [sid, qq.clock()])) as num)
          .toInt();

  // ---------------------------------------------------------------- events
  void onCheckIn(String sid) {
    final f = qq.fair();
    final s = qq.student(sid);
    final at = s['checked_in_at'] as int?;
    if (at != null && at - (f['starts_at'] as int) <= 3600 * 1000) {
      _award(sid, 'early_bird', Rules.earlyBird, ref: 'once');
    }
    refreshBadges(sid);
  }

  bool _isMatchedResume(String sid, String boothId, String? resumeId) {
    if (resumeId == null) return false;
    final f = qq.fit(sid, boothId);
    final r = qq.resume(resumeId);
    return f != null && f['resume_id'] == resumeId && r != null && r['is_default'] != 1;
  }

  int _scoredDrops(String sid) =>
      (db.scalar("SELECT COUNT(*) FROM points WHERE student_id=? AND rule='drop'", [sid]) as int);

  void onDrop(String sid, String boothId, String resumeId) {
    final fit = (qq.fit(sid, boothId)?['fit'] as num?)?.toDouble() ?? 0;
    if (_scoredDrops(sid) < Rules.maxScoredDrops) {
      final pts = fit >= 0.7 ? Rules.dropHighFit : (fit >= 0.5 ? Rules.dropMidFit : 0);
      _award(sid, 'drop', pts, boothId: boothId);
    }
    if (_isMatchedResume(sid, boothId, resumeId)) {
      _award(sid, 'matched_resume', Rules.matchedResume, boothId: boothId);
    }
    refreshBadges(sid);
  }

  void onExchange(String sid, String boothId, int exId) {
    _award(sid, 'conversation', Rules.conversation, boothId: boothId);
    final ex = db.one('SELECT * FROM exchanges WHERE id=?', [exId])!;
    if (_isMatchedResume(sid, boothId, ex['resume_id'] as String?)) {
      _award(sid, 'matched_resume', Rules.matchedResume, boothId: boothId);
    }
    final fit = (qq.fit(sid, boothId)?['fit'] as num?)?.toDouble() ?? 0;
    final q = db.one(
        "SELECT est_wait_at_join FROM queue_entries WHERE booth_id=? AND student_id=? AND status='served' ORDER BY id DESC LIMIT 1",
        [boothId, sid]);
    final waitAtJoin = (q?['est_wait_at_join'] as num?)?.toDouble() ?? 0;
    if (fit >= 0.8 && waitAtJoin < 10 && (ex['waited_min'] as num) < 15) {
      _award(sid, 'off_beaten', Rules.offBeaten, boothId: boothId);
    }
    refreshBadges(sid);
  }

  void onAskedQuestion(String sid, String boothId) {
    _award(sid, 'asked_question', Rules.askedQuestion, boothId: boothId);
    refreshBadges(sid);
  }

  void onRolodexNote(String sid, String boothId) {
    final ex = db.one('SELECT created_at FROM exchanges WHERE student_id=? AND booth_id=?', [sid, boothId]);
    if (ex != null && qq.clock() - (ex['created_at'] as int) <= 10 * 60 * 1000) {
      _award(sid, 'rolodex_note', Rules.rolodexNote, boothId: boothId);
    }
  }

  void onFollowUp(String sid, String boothId) {
    final ex = db.one('SELECT created_at FROM exchanges WHERE student_id=? AND booth_id=?', [sid, boothId]);
    if (ex == null) return;
    final now = qq.clock();
    if (now - (ex['created_at'] as int) <= 24 * 3600 * 1000) {
      final t = DateTime.fromMillisecondsSinceEpoch(now).toLocal();
      final nextDay = DateTime(t.year, t.month, t.day + 1, 9).toUtc().millisecondsSinceEpoch;
      _award(sid, 'follow_up', Rules.followUp, boothId: boothId, awardAt: nextDay);
    }
    refreshBadges(sid);
  }

  // ---------------------------------------------------------------- levels
  Map<String, Object?> level(int pts) {
    var cur = Rules.levels.first;
    Map<String, Object>? next;
    for (final l in Rules.levels) {
      if (pts >= (l['min'] as int)) {
        cur = l;
      } else {
        next ??= l;
      }
    }
    return {
      'name': cur['name'],
      'min': cur['min'],
      'next': next?['name'],
      'next_min': next?['min'],
      'to_next': next == null ? 0 : (next['min'] as int) - pts,
      'how': next == null
          ? 'Top level.'
          : 'One verified conversation is ${Rules.conversation}. A fit 70+ drop is ${Rules.dropHighFit}. A follow-up within 24 h is ${Rules.followUp}.',
    };
  }

  // ---------------------------------------------------------------- quests
  List<String> chooseQuests(String sid, {bool force = false}) {
    final cur = db.one("SELECT value FROM student_flags WHERE student_id=? AND flag='quests'", [sid]);
    if (cur != null && !force) return (jd(cur['value']) as List).cast<String>();
    final fits = db.all(
        'SELECT f.fit, f.eligible, b.category, b.id FROM fits f JOIN booths b ON b.id=f.booth_id WHERE f.student_id=? ORDER BY f.fit DESC',
        [sid]);
    final picks = <String>['question'];
    final hasShort = fits.any((f) =>
        (f['fit'] as num) >= 0.8 && f['eligible'] == 1 &&
        ((qq.lineState(f['id'] as String)['estimate'] as Map)['high_min'] as int) < 10);
    picks.add(hasShort ? 'shortwait' : 'followup');
    final topCats = fits.take(4).map((f) => f['category']).toSet();
    picks.add(topCats.length <= 2 ? 'comfort' : 'paperless');
    db.upsert('student_flags', {
      'student_id': sid,
      'flag': 'quests',
      'value': je(picks),
      'created_at': qq.clock(),
    }, ['student_id', 'flag']);
    return picks;
  }

  bool questDone(String sid, String q) {
    switch (q) {
      case 'question':
        return db.one('SELECT 1 FROM exchanges WHERE student_id=? AND asked_question=1', [sid]) != null;
      case 'shortwait':
        return db.one("SELECT 1 FROM points WHERE student_id=? AND rule='off_beaten'", [sid]) != null;
      case 'paperless':
        final flag = db.one("SELECT 1 FROM student_flags WHERE student_id=? AND flag='paperless'", [sid]) != null;
        final delivered = (db.scalar('SELECT (SELECT COUNT(*) FROM drops WHERE student_id=?)+(SELECT COUNT(*) FROM exchanges WHERE student_id=?)', [sid, sid]) as int);
        return flag && delivered >= 1;
      case 'followup':
        final met = db.all('SELECT booth_id FROM exchanges WHERE student_id=?', [sid]);
        if (met.isEmpty) return false;
        final sent = db.scalar('SELECT COUNT(*) FROM rolodex WHERE student_id=? AND email_sent_at IS NOT NULL', [sid]) as int;
        return sent >= met.length;
      case 'comfort':
        final top = db
            .all('SELECT b.category FROM fits f JOIN booths b ON b.id=f.booth_id WHERE f.student_id=? ORDER BY f.fit DESC LIMIT 3', [sid])
            .map((r) => r['category'])
            .toSet();
        return db
            .all('SELECT b.category FROM exchanges e JOIN booths b ON b.id=e.booth_id WHERE e.student_id=?', [sid])
            .any((r) => !top.contains(r['category']));
    }
    return false;
  }

  List<Map<String, Object?>> questsFor(String sid) => [
        for (final q in chooseQuests(sid)) {'id': q, 'title': questCatalog[q], 'done': questDone(sid, q)}
      ];

  void setPaperless(String sid) {
    db.upsert('student_flags', {'student_id': sid, 'flag': 'paperless', 'value': '1', 'created_at': qq.clock()},
        ['student_id', 'flag']);
    refreshBadges(sid);
  }

  // ---------------------------------------------------------------- badges
  void refreshBadges(String sid) {
    final now = qq.clock();
    void give(String b) => db.exec('INSERT OR IGNORE INTO badges (student_id, badge, earned_at) VALUES (?,?,?)', [sid, b, now]);
    if (db.one('SELECT 1 FROM exchanges WHERE student_id=?', [sid]) != null) give('first_handshake');
    if (db.one("SELECT 1 FROM points WHERE student_id=? AND rule='early_bird'", [sid]) != null) give('early_bird');
    if (db.one("SELECT 1 FROM points WHERE student_id=? AND rule='off_beaten'", [sid]) != null) give('off_beaten');
    if (questDone(sid, 'paperless')) give('paperless');
    if (questDone(sid, 'followup')) give('follow_through');
    final qs = chooseQuests(sid);
    if (qs.length == 3 && qs.every((q) => questDone(sid, q))) give('full_house');
    qq.changed(['student:$sid']);
  }

  Map<String, Object?> summary(String sid) {
    final pts = totalPoints(sid);
    final earned = {
      for (final r in db.all('SELECT * FROM badges WHERE student_id=?', [sid])) r['badge'] as String: r['earned_at']
    };
    return {
      'points': pts,
      'pending_points': pendingPoints(sid),
      'level': level(pts),
      'quests': questsFor(sid),
      'badges': [
        for (final e in badgeCatalog.entries)
          {'id': e.key, ...e.value, 'earned': earned.containsKey(e.key), 'earned_at': earned[e.key]}
      ],
      'ledger': db
          .all('SELECT p.rule, p.points, p.created_at, p.award_at, b.name AS booth FROM points p LEFT JOIN booths b ON b.id=p.booth_id '
              'WHERE p.student_id=? ORDER BY p.created_at DESC', [sid])
          .map((r) => {...r, 'pending': (r['award_at'] as int) > qq.clock()})
          .toList(),
      'rules': Rules.table,
    };
  }

  // ---------------------------------------------------------------- leaderboard
  Map<String, Object?> leaderboard(String sid) {
    final me = qq.student(sid);
    final friends = db.all(
        'SELECT s.* FROM friends f JOIN students s ON s.id=f.friend_id WHERE f.student_id=? AND s.leaderboard_opt_in=1', [sid]);
    final rows = [
      if (me['leaderboard_opt_in'] == 1) me,
      ...friends,
    ];
    final board = [
      for (final r in rows)
        {
          'id': r['id'],
          'name': r['id'] == sid ? '${r['name']} (you)' : r['name'],
          'avatar': r['avatar'],
          'points': totalPoints(r['id'] as String),
          'level': level(totalPoints(r['id'] as String))['name'],
          'me': r['id'] == sid,
        }
    ]..sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
    // Campus-wide: only my percentile. Never other students' names.
    final all = db.all('SELECT id FROM students WHERE checked_in_at IS NOT NULL').map((r) => totalPoints(r['id'] as String)).toList();
    final mine = totalPoints(sid);
    final below = all.where((p) => p < mine).length;
    final eq = all.where((p) => p == mine).length;
    final pct = all.isEmpty ? 0 : (((below + 0.5 * eq) / all.length) * 100).round();
    return {
      'opted_in': me['leaderboard_opt_in'] == 1,
      'friends': board,
      'campus_percentile': pct,
      'campus_size': all.length,
      'note': 'Points never change what recruiters see or the order they see it in.',
    };
  }

  // ---------------------------------------------------------------- recap
  Map<String, Object?> recap(String sid) {
    final s = qq.student(sid);
    final ex = db.all('SELECT e.*, b.name FROM exchanges e JOIN booths b ON b.id=e.booth_id WHERE e.student_id=?', [sid]);
    final ds = db.all('SELECT d.*, b.name FROM drops d JOIN booths b ON b.id=d.booth_id WHERE d.student_id=?', [sid]);
    final drops = ds.where((d) => d['kind'] == 'drop').length;
    final fp = ds.where((d) => d['kind'] == 'fairplay').toList();
    final lc = ds.where((d) => d['kind'] == 'line_credit').length;
    final metIds = ex.map((e) => e['booth_id']).toSet();
    // Minutes saved: booths reached by resume without standing in that line.
    var saved = 0.0;
    for (final d in ds) {
      if (d['kind'] == 'line_credit' || metIds.contains(d['booth_id'])) continue;
      saved += (d['est_wait_min'] as num).toDouble();
    }
    final waits = db.all(
        "SELECT q.booth_id, b.name, (COALESCE(q.left_at, ?) - q.joined_at)/60000.0 AS m FROM queue_entries q JOIN booths b ON b.id=q.booth_id WHERE q.student_id=?",
        [qq.clock(), sid]);
    final waitedTotal = waits.fold<double>(0, (a, r) => a + (r['m'] as num).toDouble());
    final fits = db.all(
        'SELECT f.*, b.name, b.id AS bid FROM fits f JOIN booths b ON b.id=f.booth_id WHERE f.student_id=? ORDER BY f.fit DESC', [sid]);
    final best = fits.where((f) => f['eligible'] == 1).firstOrNull ?? fits.firstOrNull;
    final pts = totalPoints(sid);
    final g = summary(sid);

    // Two specific, honest suggestions. No generic praise.
    final tips = <String>[];
    final longest = waits.isEmpty ? null : waits.reduce((a, b) => (a['m'] as num) >= (b['m'] as num) ? a : b);
    if (longest != null && (longest['m'] as num) >= 30) {
      final alt = fits
          .where((f) => f['eligible'] == 1 && (f['fit'] as num) >= 0.85 && !metIds.contains(f['bid']) && f['bid'] != longest['booth_id'])
          .where((f) => (db.scalar('SELECT est_wait_at_join FROM queue_entries WHERE booth_id=? ORDER BY joined_at DESC LIMIT 1', [f['bid']]) as num? ?? 0) < 10 ||
              qq.avgServiceMin(f['bid'] as String) * qq.waiting(f['bid'] as String).length < 10)
          .map((f) => f['name'])
          .toList();
      if (alt.isNotEmpty) {
        tips.add('You spent ${(longest['m'] as num).round()} min in one line (${longest['name']}); '
            '${alt.length == 1 ? 'one booth' : '${_n(alt.length)} booths'} with fit 85+ had under 10 min waits (${alt.take(3).join(', ')}).');
      }
    }
    final noNote = db.scalar("SELECT COUNT(*) FROM rolodex WHERE student_id=? AND (note IS NULL OR note='')", [sid]) as int;
    if (ex.isNotEmpty && noNote > 0) {
      tips.add('$noNote of your ${ex.length} conversations ${noNote == 1 ? 'has' : 'have'} no note. A note written right after the chat makes the follow-up email specific.');
    }
    final notSent = db.scalar('SELECT COUNT(*) FROM rolodex WHERE student_id=? AND email_sent_at IS NULL', [sid]) as int;
    if (ex.isNotEmpty && notSent > 0) {
      tips.add('$notSent follow-up ${notSent == 1 ? 'email is' : 'emails are'} not sent yet. Send by tomorrow while the recruiter remembers the conversation.');
    }
    final lowDrops = ds.where((d) => d['kind'] == 'drop').where((d) {
      final f = qq.fit(sid, d['booth_id'] as String);
      return ((f?['fit'] as num?) ?? 0) < 0.5;
    }).toList();
    if (lowDrops.isNotEmpty) {
      tips.add('${lowDrops.length} of your drops went to booths with fit under 50 (${lowDrops.map((d) => d['name']).join(', ')}). Fair Play already covers your top 3; spend drops on fit 70+.');
    }
    if (ex.isNotEmpty && !ex.any((e) => e['asked_question'] == 1)) {
      tips.add('You did not log asking your pitch question at any booth. A role-specific question is what recruiters tend to remember.');
    }
    if (ex.isEmpty) {
      tips.add('No recruiter confirmed a conversation today. Recruiters see in-person conversations first, so one short line at a high-fit booth moves you up more than extra drops.');
    }
    if (tips.length < 2 && best != null && !metIds.contains(best['bid'])) {
      tips.add('Your best fit, ${best['name']} (fit ${((best['fit'] as num) * 100).round()}), got your resume but no conversation. Next fair, visit it first.');
    }
    return {
      'name': s['name'],
      'avatar': s['avatar'],
      'conversations': ex.length,
      'conversation_booths': ex.map((e) => e['name']).toList(),
      'resumes_delivered': {'total': drops + fp.length + lc, 'drops': drops, 'fair_play': fp.length, 'line_credit': lc},
      'fair_play_booths': fp.map((d) => d['name']).toList(),
      'minutes_saved': saved.round(),
      'minutes_in_line': waitedTotal.round(),
      'best_fit': best == null ? null : {'name': best['name'], 'fit_pct': ((best['fit'] as num) * 100).round()},
      'badges': (g['badges'] as List).where((b) => (b as Map)['earned'] == true).toList(),
      'points': pts,
      'pending_points': pendingPoints(sid),
      'level': level(pts),
      'suggestions': tips.take(2).toList(),
      'fair_closed': !qq.fairOpen,
    };
  }

  static String _n(int n) => const ['zero', 'one', 'two', 'three', 'four', 'five'][min(n, 5)];
}

/// Small helper reused by the recap to stay consistent with the queue screen.
String waitLabel(int ahead, double avg) => WaitEstimate.of(ahead, avg).label;
