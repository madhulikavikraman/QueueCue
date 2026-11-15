import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// Recruiter shortlist sections, in display order.
enum Section { met, waited, sent }

extension SectionLabel on Section {
  String get key => name;
  String get label => switch (this) {
        Section.met => 'Met you in person',
        Section.waited => 'Waited for you',
        Section.sent => 'Sent their resume',
      };
}

class FairnessSettings {
  final double wFit;
  final double wEffort;
  final int capMin;
  final String seed;
  const FairnessSettings(
      {this.wFit = 0.85, this.wEffort = 0.15, this.capMin = 60, required this.seed});

  String get formula =>
      'Score = ${wFit.toStringAsFixed(2)} x Fit + ${wEffort.toStringAsFixed(2)} x Effort. '
      'Effort = min(minutes waited in this line, $capMin) / $capMin. '
      'Sections first: Met in person > Waited for you > Sent their resume. '
      'Ties: committed lottery.';
}

/// Everything we know about a student for one booth. Several fields (name,
/// arrival time, points, level, grad year) are carried ONLY so tests can prove
/// they have no effect. The engine never reads them.
class Candidate {
  final String studentId;
  final double fit; // 0..1, blind
  final double waitedMin; // minutes in this booth's line, incl. line credit
  final bool verified; // recruiter-confirmed conversation
  final bool lineCredit; // in line when booth closed / recruiter left
  final bool sent; // drop or Fair Play match

  // Not used in Score. Present to make invariance testable.
  final String name;
  final int arrivalMs;
  final int points;
  final int level;
  final int gradYear;

  const Candidate({
    required this.studentId,
    required this.fit,
    required this.waitedMin,
    this.verified = false,
    this.lineCredit = false,
    this.sent = false,
    this.name = '',
    this.arrivalMs = 0,
    this.points = 0,
    this.level = 0,
    this.gradYear = 0,
  });

  Candidate copyWith(
          {String? name,
          int? arrivalMs,
          int? points,
          int? level,
          int? gradYear,
          double? waitedMin,
          double? fit}) =>
      Candidate(
        studentId: studentId,
        fit: fit ?? this.fit,
        waitedMin: waitedMin ?? this.waitedMin,
        verified: verified,
        lineCredit: lineCredit,
        sent: sent,
        name: name ?? this.name,
        arrivalMs: arrivalMs ?? this.arrivalMs,
        points: points ?? this.points,
        level: level ?? this.level,
        gradYear: gradYear ?? this.gradYear,
      );
}

class Ranked {
  final Candidate c;
  final Section section;
  final double effort;
  final double score;
  final String tieKey;
  int rank = 0; // 1-based, overall
  int sectionRank = 0;
  Ranked(this.c, this.section, this.effort, this.score, this.tieKey);

  bool get strongUnmet => section == Section.sent && c.fit >= 0.85;

  Map<String, Object?> toJson() => {
        'student_id': c.studentId,
        'section': section.key,
        'fit': _r(c.fit),
        'effort': _r(effort),
        'score': _r(score),
        'waited_min': _r(c.waitedMin, 1),
        'rank': rank,
        'section_rank': sectionRank,
        'strong_unmet': strongUnmet,
        'tie_key': tieKey.substring(0, 10),
      };
}

double _r(double v, [int d = 3]) => double.parse(v.toStringAsFixed(d));

class FairnessEngine {
  final FairnessSettings s;
  const FairnessEngine(this.s);

  static String sha256Hex(String v) => sha256.convert(utf8.encode(v)).toString();

  Section sectionOf(Candidate c) {
    if (c.verified) return Section.met;
    if (c.lineCredit) return Section.waited;
    return Section.sent;
  }

  double effort(Candidate c) {
    if (s.capMin <= 0) return 0;
    final w = c.waitedMin.isNaN ? 0.0 : c.waitedMin;
    return math.min(math.max(w, 0.0), s.capMin.toDouble()) / s.capMin;
  }

  double score(Candidate c) => s.wFit * c.fit.clamp(0.0, 1.0) + s.wEffort * effort(c);

  /// Lottery key: committed seed + booth + student id. Re-runnable by anyone
  /// once the seed is revealed at close.
  String tieKey(String boothId, Candidate c) =>
      sha256Hex('${s.seed}:$boothId:${c.studentId}');

  List<Ranked> rank(String boothId, Iterable<Candidate> cands) {
    final list = [
      for (final c in cands)
        Ranked(c, sectionOf(c), effort(c), score(c), tieKey(boothId, c))
    ];
    list.sort((a, b) {
      final s1 = a.section.index.compareTo(b.section.index);
      if (s1 != 0) return s1;
      // Compare on a fixed precision so float noise cannot act as a tiebreak.
      final sa = (a.score * 1e9).round();
      final sb = (b.score * 1e9).round();
      final s2 = sb.compareTo(sa);
      if (s2 != 0) return s2;
      return a.tieKey.compareTo(b.tieKey);
    });
    final perSection = <Section, int>{};
    for (var i = 0; i < list.length; i++) {
      list[i].rank = i + 1;
      final n = (perSection[list[i].section] ?? 0) + 1;
      perSection[list[i].section] = n;
      list[i].sectionRank = n;
    }
    return list;
  }

  /// Largest fit gap that waiting alone can overcome.
  double get maxFitGapFromWaiting => s.wFit == 0 ? 1 : s.wEffort / s.wFit;

  /// A plain-language receipt for "Why am I here?".
  Map<String, Object?> receipt(String boothId, Candidate c, List<Ranked> ranked) {
    final r = ranked.firstWhere((x) => x.c.studentId == c.studentId);
    return {
      'fit': _r(c.fit),
      'waited_min': _r(c.waitedMin, 1),
      'effort': _r(r.effort),
      'score': _r(r.score),
      'section': r.section.key,
      'section_label': r.section.label,
      'section_rank': r.sectionRank,
      'section_size': ranked.where((x) => x.section == r.section).length,
      'formula': s.formula,
      'worked':
          '${s.wFit.toStringAsFixed(2)} x ${c.fit.toStringAsFixed(2)} + ${s.wEffort.toStringAsFixed(2)} x ${r.effort.toStringAsFixed(2)} = ${r.score.toStringAsFixed(3)}',
      'not_used': [
        'Fair Play points',
        'level',
        'badges',
        'arrival time of day',
        'name',
        'school year',
        'anything identity-related'
      ],
    };
  }
}

/// Wait estimate shown as a range; never a single precise number.
class WaitEstimate {
  final int ahead;
  final double avgServiceMin;
  final int lowMin;
  final int highMin;
  const WaitEstimate(this.ahead, this.avgServiceMin, this.lowMin, this.highMin);

  static WaitEstimate of(int ahead, double avgServiceMin) {
    if (ahead <= 0) return WaitEstimate(0, avgServiceMin, 0, 0);
    final est = ahead * avgServiceMin;
    int floor5(double v) => (v / 5).floor() * 5;
    int ceil5(double v) => (v / 5).ceil() * 5;
    var lo = floor5(est * 0.9);
    var hi = ceil5(est * 1.1);
    if (est < 10) {
      lo = math.max(0, (est * 0.8).floor());
      hi = math.max(lo + 2, (est * 1.25).ceil());
    }
    if (hi <= lo) hi = lo + 5;
    return WaitEstimate(ahead, avgServiceMin, lo, hi);
  }

  String get label => ahead == 0
      ? 'You are next'
      : (highMin <= 3 ? 'under 5 min' : '~$lowMin to $highMin min');

  Map<String, Object?> toJson() => {
        'ahead': ahead,
        'avg_service_min': double.parse(avgServiceMin.toStringAsFixed(2)),
        'low_min': lowMin,
        'high_min': highMin,
        'label': label,
      };
}

/// Rolling average service time from card-exchange timestamps.
double rollingServiceMin(List<double> recentServiceSec, double defaultMin,
    {int window = 8}) {
  final xs = recentServiceSec
      .where((s) => s > 20 && s < 20 * 60)
      .take(window)
      .toList();
  if (xs.length < 2) return defaultMin;
  final avg = xs.reduce((a, b) => a + b) / xs.length / 60.0;
  return avg;
}

/// Pearson correlation; returns 0 for degenerate input.
double pearson(List<double> xs, List<double> ys) {
  final n = math.min(xs.length, ys.length);
  if (n < 3) return 0;
  final mx = xs.take(n).reduce((a, b) => a + b) / n;
  final my = ys.take(n).reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - mx, dy = ys[i] - my;
    sxy += dx * dy;
    sxx += dx * dx;
    syy += dy * dy;
  }
  if (sxx == 0 || syy == 0) return 0;
  return sxy / math.sqrt(sxx * syy);
}

/// Piles: index 0-1 are "high", index 2+ are "low". Piles are renameable, so
/// we work by position, not by name.
bool isHighPile(List<String> piles, String? pile) {
  if (pile == null) return false;
  final i = piles.indexOf(pile);
  return i == 0 || i == 1;
}

bool isLowPile(List<String> piles, String? pile) {
  if (pile == null) return false;
  final i = piles.indexOf(pile);
  return i >= 2;
}
