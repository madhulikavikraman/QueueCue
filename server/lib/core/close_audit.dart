import '../fairness/fairness_engine.dart';
import 'qq.dart';

extension CloseAudit on QQ {
  /// Line credit: everyone still waiting moves to the recruiter's inbox,
  /// flagged with how long they waited. Arriving last does not jump anyone:
  /// the credit section is ordered by the same Score as every other section.
  int closeBooth(String boothId, {String reason = 'closed'}) {
    booth(boothId); // 404 if unknown
    final now = clock();
    var n = 0;
    db.tx(() {
      for (final q in waiting(boothId)) {
        final waited = (now - (q['joined_at'] as int)) / 60000.0;
        db.exec("UPDATE queue_entries SET status='credited', left_at=? WHERE id=?", [now, q['id']]);
        final sid = q['student_id'] as String;
        final resumeId = q['resume_id'] ?? fit(sid, boothId)?['resume_id'];
        db.insert('drops', {
          'booth_id': boothId,
          'student_id': sid,
          'resume_id': resumeId,
          'note': null,
          'kind': 'line_credit',
          'waited_min': waited,
          'est_wait_min': 0,
          'created_at': now,
        });
        if (resumeId != null) jobs.ensureSummary(boothId, sid, resumeId as String);
        changed(['student:$sid']);
        n++;
      }
      db.exec("UPDATE booths SET status='closed' WHERE id=?", [boothId]);
    });
    changed(['booth:$boothId', 'organizer', 'fair']);
    return n;
  }

  void reopenBooth(String boothId) {
    db.exec("UPDATE booths SET status='open' WHERE id=?", [boothId]);
    changed(['booth:$boothId', 'organizer', 'fair']);
  }

  /// Top-3 eligible booths by fit (major + work authorization), excluding any
  /// the student unticked. Points, level and arrival time are never read.
  List<Map<String, Object?>> fairPlayTargets(String sid, {bool includeExcluded = false}) {
    final s = student(sid);
    final rows = db.all(
        'SELECT f.*, b.name, b.number, b.citizenship_required, b.sponsors, b.majors_json, b.partial_majors_json '
        'FROM fits f JOIN booths b ON b.id=f.booth_id WHERE f.student_id=? ORDER BY f.fit DESC, b.number', [sid]);
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final el = eligibility(s, booth(r['booth_id'] as String));
      if (el['eligible'] != true) continue;
      final excluded = db.one('SELECT excluded FROM fairplay_prefs WHERE student_id=? AND booth_id=?',
              [sid, r['booth_id']])?['excluded'] ==
          1;
      final reached = db.one(
              "SELECT 'x' FROM exchanges WHERE student_id=? AND booth_id=? UNION SELECT kind FROM drops WHERE student_id=? AND booth_id=?",
              [sid, r['booth_id'], sid, r['booth_id']]) !=
          null;
      final via = db.one(
          "SELECT CASE WHEN EXISTS(SELECT 1 FROM exchanges WHERE student_id=?1 AND booth_id=?2) THEN 'conversation' "
          "ELSE (SELECT kind FROM drops WHERE student_id=?1 AND booth_id=?2 ORDER BY created_at LIMIT 1) END AS via",
          [sid, r['booth_id']])?['via'];
      out.add({
        'booth_id': r['booth_id'],
        'name': r['name'],
        'number': r['number'],
        'fit': r['fit'],
        'fit_pct': ((r['fit'] as num) * 100).round(),
        'resume_id': r['resume_id'],
        'resume_label': resume(r['resume_id'] as String?)?['label'],
        'excluded': excluded,
        'already_reached': reached,
        'reached_via': via,
      });
    }
    final active = out.where((x) => includeExcluded || x['excluded'] != true).toList();
    if (!includeExcluded) return active.take(3).toList();
    // Preview: top 3 not-excluded plus any excluded ones that would be in top 3.
    final res = <Map<String, Object?>>[];
    var kept = 0;
    for (final x in out) {
      if (x['excluded'] == true) {
        if (kept < 3) res.add(x);
      } else if (kept < 3) {
        res.add(x);
        kept++;
      }
    }
    return res;
  }

  Map<String, Object?> fairPlayStatus(String sid) {
    final delivered = db.all(
        "SELECT d.*, b.name, b.number FROM drops d JOIN booths b ON b.id=d.booth_id WHERE d.student_id=? AND d.kind='fairplay'", [sid]);
    final targets = fairPlayTargets(sid, includeExcluded: true);
    final reached = targets.where((t) => t['excluded'] != true && (t['already_reached'] == true)).length;
    return {
      'fair_closed': !fairOpen,
      'targets': targets,
      'delivered': [
        for (final d in delivered) {'booth_id': d['booth_id'], 'name': d['name'], 'number': d['number'], 'at': d['created_at']}
      ],
      'reached_count': reached,
      'message': !fairOpen
          ? 'Your resume reached $reached best-fit recruiter${reached == 1 ? '' : 's'}.'
          : 'When the fair closes, your best-matched resume goes to your top 3 fit recruiters, even if you never reach their booths. Untick any you do not want.',
    };
  }

  void setFairPlayPref(String sid, String boothId, bool excluded) {
    if (!fairOpen) throw ApiError(409, 'The fair has closed; Fair Play matches were already sent.');
    db.upsert('fairplay_prefs', {'student_id': sid, 'booth_id': boothId, 'excluded': excluded ? 1 : 0},
        ['student_id', 'booth_id']);
    changed(['student:$sid']);
  }

  /// Close the fair: line credit at every booth, then Fair Play matches for
  /// every checked-in student, then reveal the lottery seed.
  Map<String, Object?> closeFair() {
    if (!fairOpen) throw ApiError(409, 'Already closed.');
    var credited = 0;
    for (final b in booths()) {
      credited += closeBooth(b['id'] as String, reason: 'fair closed');
    }
    final now = clock();
    var matches = 0;
    final students = db.all('SELECT id FROM students WHERE checked_in_at IS NOT NULL');
    db.tx(() {
      for (final s in students) {
        final sid = s['id'] as String;
        for (final t in fairPlayTargets(sid)) {
          if (t['already_reached'] == true) continue;
          db.insert('drops', {
            'booth_id': t['booth_id'],
            'student_id': sid,
            'resume_id': t['resume_id'],
            'kind': 'fairplay',
            'est_wait_min': (WaitEstimate.of(waiting(t['booth_id'] as String).length,
                    avgServiceMin(t['booth_id'] as String)))
                .highMin
                .toDouble(),
            'created_at': now,
          });
          matches++;
        }
      }
      db.exec("UPDATE fairs SET status='closed', closed_at=?", [now]);
    });
    // Summaries for Fair Play matches (background).
    for (final d in db.all("SELECT booth_id, student_id, resume_id FROM drops WHERE kind='fairplay' AND resume_id IS NOT NULL")) {
      jobs.ensureSummary(d['booth_id'] as String, d['student_id'] as String, d['resume_id'] as String);
    }
    changed(['fair', 'organizer', for (final b in booths()) 'booth:${b['id']}', for (final s in students) 'student:${s['id']}']);
    return {
      'line_credits': credited,
      'fair_play_matches': matches,
      'students': students.length,
      'seed': fair()['seed'],
      'message': 'Fair closed. $credited line credits and $matches Fair Play matches sent to ${students.length} students.',
    };
  }

  /// Post-fair audit. Works during the fair too (on current shortlists).
  Map<String, Object?> audit() {
    final xs = <double>[];
    final ys = <double>[];
    final wx = <double>[]; // within-section: what the Score formula controls
    final wy = <double>[];
    final byHour = <int, List<double>>{};
    final rows = <Map<String, Object?>>[];
    for (final b in booths()) {
      final ranked = rankBooth(b['id'] as String);
      final n = ranked.length;
      if (n < 2) continue;
      for (final r in ranked) {
        final arr = _arrivalAt(b['id'] as String, r.c.studentId);
        if (arr == null) continue;
        final dt = DateTime.fromMillisecondsSinceEpoch(arr).toLocal();
        final tod = dt.hour * 60 + dt.minute + 0.0;
        final pr = (r.rank - 1) / (n - 1); // 0 = top
        xs.add(tod);
        ys.add(pr);
        final secN = ranked.where((x) => x.section == r.section).length;
        if (secN >= 2) {
          wx.add(tod);
          wy.add((r.sectionRank - 1) / (secN - 1));
        }
        byHour.putIfAbsent(dt.hour, () => []).add(pr);
        rows.add({'booth': b['name'], 'student_id': r.c.studentId, 'arrival_min_of_day': tod.round(), 'rank_pct': pr, 'section': r.section.key});
      }
    }
    final corr = pearson(wx, wy);
    final overall = pearson(xs, ys);
    final hours = (byHour.keys.toList()..sort())
        .map((h) => {
              'hour': h,
              'label': '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'am' : 'pm'}',
              'avg_rank_pct': double.parse((byHour[h]!.reduce((a, c) => a + c) / byHour[h]!.length).toStringAsFixed(3)),
              'n': byHour[h]!.length,
            })
        .toList();

    // Fair Play delivery by group: reached top-3 / 3, averaged per group.
    Map<String, Object?> groupRates(String col, String Function(String) label) {
      final groups = <String, List<double>>{};
      final counts = <String, int>{};
      for (final s in db.all('SELECT id, $col AS g FROM students WHERE checked_in_at IS NOT NULL')) {
        final sid = s['id'] as String;
        final t = fairPlayTargets(sid);
        final reached = t.where((x) => x['already_reached'] == true).length;
        final fp = db.scalar("SELECT COUNT(*) FROM drops WHERE student_id=? AND kind='fairplay'", [sid]) as int;
        final g = label(s['g'] as String);
        groups.putIfAbsent(g, () => []).add(fairOpen ? t.length / 3 : reached / 3);
        counts[g] = (counts[g] ?? 0) + fp;
      }
      final rates = {for (final e in groups.entries) e.key: e.value.reduce((a, c) => a + c) / e.value.length};
      final best = rates.values.fold<double>(0, (a, c) => c > a ? c : a);
      return {
        'groups': [
          for (final e in rates.entries)
            {
              'group': e.key,
              'students': groups[e.key]!.length,
              'fair_play_matches': counts[e.key],
              'rate': double.parse(e.value.toStringAsFixed(3)),
              'ratio_to_best': best == 0 ? 1.0 : double.parse((e.value / best).toStringAsFixed(3)),
              'flag': best > 0 && e.value / best < 0.8,
            }
        ]..sort((a, c) => (a['group'] as String).compareTo(c['group'] as String)),
      };
    }

    final f = fair();
    return {
      'fair_status': f['status'],
      'arrival_rank_correlation': double.parse(corr.toStringAsFixed(3)),
      'correlation_note': corr.abs() < 0.2
          ? 'Near zero: within each section, arrival time does not predict shortlist rank.'
          : 'Not near zero. Check the fit scores of early vs late arrivals at the busiest booths.',
      'overall_correlation': double.parse(overall.toStringAsFixed(3)),
      'overall_note': 'Across sections, later arrivals are more often still in line at close, so they land in "Waited for you" '
          'instead of "Met you in person". That is time at the fair, not ordering; within each section the order ignores arrival time.',
      'avg_rank_by_hour': hours,
      'fair_play_by_major': groupRates('major', (g) => g),
      'fair_play_by_work_auth': groupRates('work_auth', fmtWorkAuth),
      'rate_meaning': fairOpen
          ? 'Before close: share of each group\'s guaranteed 3 that have an eligible target.'
          : 'Share of each group\'s top-3 fit recruiters that received their resume.',
      'seed_hash': f['seed_hash'],
      'seed': f['status'] == 'closed' ? f['seed'] : null,
      'seed_note': f['status'] == 'closed'
          ? 'Seed revealed. Anyone can recompute tie-breaks: SHA-256(seed + ":" + boothId + ":" + studentId), ascending.'
          : 'Seed is committed (hash shown) and revealed when the fair closes.',
      'n_points': xs.length,
      'rows': rows,
    };
  }

  int? _arrivalAt(String boothId, String sid) {
    final v = db.scalar(
        'SELECT MIN(t) FROM (SELECT joined_at AS t FROM queue_entries WHERE booth_id=?1 AND student_id=?2 '
        'UNION ALL SELECT created_at FROM drops WHERE booth_id=?1 AND student_id=?2 AND kind IN (\'drop\') '
        'UNION ALL SELECT created_at FROM exchanges WHERE booth_id=?1 AND student_id=?2)',
        [boothId, sid]);
    return v as int?;
  }

  String auditCsv() {
    final a = audit();
    final b = StringBuffer();
    b.writeln('metric,value');
    b.writeln('arrival_rank_correlation_within_section,${a['arrival_rank_correlation']}');
    b.writeln('arrival_rank_correlation_overall,${a['overall_correlation']}');
    b.writeln('seed_hash,${a['seed_hash']}');
    b.writeln('seed,${a['seed'] ?? '(revealed at close)'}');
    b.writeln();
    b.writeln('hour,avg_rank_pct,n');
    for (final h in a['avg_rank_by_hour'] as List) {
      b.writeln('${h['label']},${h['avg_rank_pct']},${h['n']}');
    }
    for (final k in ['fair_play_by_major', 'fair_play_by_work_auth']) {
      b.writeln();
      b.writeln('$k,students,fair_play_matches,rate,ratio_to_best,below_four_fifths');
      for (final g in ((a[k] as Map)['groups'] as List)) {
        b.writeln('"${g['group']}",${g['students']},${g['fair_play_matches']},${g['rate']},${g['ratio_to_best']},${g['flag']}');
      }
    }
    b.writeln();
    b.writeln('booth,student_id,arrival_min_of_day,rank_pct,section');
    for (final r in a['rows'] as List) {
      b.writeln('"${r['booth']}",${r['student_id']},${r['arrival_min_of_day']},${(r['rank_pct'] as double).toStringAsFixed(3)},${r['section']}');
    }
    return b.toString();
  }

  Map<String, Object?> organizerView() {
    final f = fair();
    final bs = booths();
    return {
      'fair': {
        'id': f['id'],
        'name': f['name'],
        'venue': f['venue'],
        'status': f['status'],
        'starts_at': f['starts_at'],
        'ends_at': f['ends_at'],
        'closed_at': f['closed_at'],
        'seed_hash': f['seed_hash'],
        'seed': f['status'] == 'closed' ? f['seed'] : null,
        'w_fit': f['w_fit'],
        'w_effort': f['w_effort'],
        'effort_cap_min': f['effort_cap_min'],
        'floor_w': f['floor_w'],
        'floor_h': f['floor_h'],
      },
      'demo_mode': demoMode,
      'ai_live': aiLive,
      'simulating': simulating,
      'booths': [
        for (final b in bs)
          {
            ...publicBooth(b),
            'line': waiting(b['id'] as String).length,
            'estimate': WaitEstimate.of(waiting(b['id'] as String).length, avgServiceMin(b['id'] as String)).toJson(),
            'met': db.scalar('SELECT COUNT(*) FROM exchanges WHERE booth_id=?', [b['id']]),
            'drops': db.scalar("SELECT COUNT(*) FROM drops WHERE booth_id=? AND kind='drop'", [b['id']]),
            'booth_key': b['booth_key'],
            'join_token': codes.boothJoinToken(b['id'] as String),
          }
      ],
      'stats': {
        'checked_in': db.scalar('SELECT COUNT(*) FROM students WHERE checked_in_at IS NOT NULL'),
        'in_lines': db.scalar("SELECT COUNT(*) FROM queue_entries WHERE status='waiting'"),
        'conversations': db.scalar('SELECT COUNT(*) FROM exchanges'),
        'drops': db.scalar("SELECT COUNT(*) FROM drops WHERE kind='drop'"),
        'fair_play': db.scalar("SELECT COUNT(*) FROM drops WHERE kind='fairplay'"),
        'line_credit': db.scalar("SELECT COUNT(*) FROM drops WHERE kind='line_credit'"),
      },
      'access_requests': db
          .all('SELECT a.*, s.name, s.avatar, b.name AS booth_name, b.number AS booth_number FROM access_requests a '
              'JOIN students s ON s.id=a.student_id LEFT JOIN booths b ON b.id=a.booth_id ORDER BY a.status, a.created_at DESC')
          .toList(),
    };
  }

  void updateSettings({double? wFit, double? wEffort, int? capMin}) {
    if (wFit != null && (wFit < 0 || wFit > 1)) throw ApiError(400, 'Fit weight must be 0 to 1.');
    if (wFit != null && wEffort == null) wEffort = double.parse((1 - wFit).toStringAsFixed(2));
    if (capMin != null && (capMin < 5 || capMin > 240)) throw ApiError(400, 'Cap must be 5 to 240 minutes.');
    final f = fair();
    db.exec('UPDATE fairs SET w_fit=?, w_effort=?, effort_cap_min=?', [
      wFit ?? f['w_fit'],
      wEffort ?? f['w_effort'],
      capMin ?? f['effort_cap_min'],
    ]);
    changed(['fair', 'organizer', for (final b in booths()) 'booth:${b['id']}']);
  }

  void resolveAccess(int id) {
    db.exec("UPDATE access_requests SET status='resolved', resolved_at=? WHERE id=?", [clock(), id]);
    changed(['organizer']);
  }
}
