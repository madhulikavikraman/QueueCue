import 'dart:math';

import 'package:queuecue_server/fairness/fairness_engine.dart';
import 'package:test/test.dart';

/// Property-based invariance tests for the fairness engine.
/// Each property runs on many random shortlists.
void main() {
  const iterations = 300;
  final settings = const FairnessSettings(seed: 'committed-seed-for-tests');
  final engine = FairnessEngine(settings);

  List<Candidate> randomShortlist(Random r, {int? n}) {
    final count = n ?? 5 + r.nextInt(60);
    return [
      for (var i = 0; i < count; i++)
        Candidate(
          studentId: 'stu-$i-${r.nextInt(1 << 30)}',
          // Coarse fits create plenty of exact ties to exercise the lottery.
          fit: (r.nextInt(21) * 5) / 100,
          waitedMin: r.nextInt(4) == 0 ? 0 : r.nextDouble() * 120,
          verified: r.nextInt(3) == 0,
          lineCredit: r.nextInt(5) == 0,
          sent: true,
          name: 'Name $i',
          arrivalMs: r.nextInt(1 << 31),
          points: r.nextInt(300),
          level: r.nextInt(4),
          gradYear: 2024 + r.nextInt(4),
        )
    ];
  }

  List<String> order(List<Candidate> cs) =>
      engine.rank('booth-x', cs).map((r) => r.c.studentId).toList();

  group('Invariance: identity, arrival time, points and level never change the order', () {
    test('random changes to name, arrival time of day, points, level and grad year', () {
      final r = Random(1);
      for (var it = 0; it < iterations; it++) {
        final cs = randomShortlist(r);
        final before = order(cs);
        final mutated = [
          for (final c in cs)
            c.copyWith(
              name: 'Someone Else ${r.nextInt(99999)}',
              arrivalMs: r.nextInt(1 << 31),
              points: r.nextInt(10000),
              level: r.nextInt(4),
              gradYear: 2020 + r.nextInt(10),
            )
        ]..shuffle(r); // input order must not matter either
        expect(order(mutated), equals(before), reason: 'iteration $it');
      }
    });
  });

  group('Sections', () {
    test('every verified-conversation student appears above every non-verified student', () {
      final r = Random(2);
      for (var it = 0; it < iterations; it++) {
        final ranked = engine.rank('b', randomShortlist(r));
        final lastMet = ranked.lastIndexWhere((x) => x.c.verified);
        final firstNot = ranked.indexWhere((x) => !x.c.verified);
        if (lastMet >= 0 && firstNot >= 0) {
          expect(lastMet, lessThan(firstNot), reason: 'iteration $it');
        }
      }
    });

    test('line credit ("Waited for you") sits above remote resumes, below verified', () {
      final r = Random(3);
      for (var it = 0; it < iterations; it++) {
        final ranked = engine.rank('b', randomShortlist(r));
        final idx = ranked.map((x) => x.section.index).toList();
        final sorted = [...idx]..sort();
        expect(idx, equals(sorted));
      }
    });

    test('a highly qualified remote candidate is flagged as a strong unmet match', () {
      final ranked = engine.rank('b', [
        const Candidate(studentId: 'met', fit: 0.4, waitedMin: 30, verified: true),
        const Candidate(studentId: 'remote', fit: 0.9, waitedMin: 0, sent: true),
      ]);
      expect(ranked.first.c.studentId, 'met');
      expect(ranked.last.strongUnmet, isTrue);
    });
  });

  group('Effort cap', () {
    test('changing only wait minutes changes order only within the effort cap', () {
      final r = Random(4);
      final maxGap = settings.wEffort / settings.wFit; // ~0.176
      for (var it = 0; it < iterations; it++) {
        final cs = randomShortlist(r);
        final before = engine.rank('b', cs);
        final pos = {for (final x in before) x.c.studentId: x.rank};
        final changed = [for (final c in cs) c.copyWith(waitedMin: r.nextDouble() * 200)];
        final after = engine.rank('b', changed);
        final pos2 = {for (final x in after) x.c.studentId: x.rank};
        final fit = {for (final c in cs) c.studentId: c.fit};
        final sec = {for (final x in before) x.c.studentId: x.section};
        final ids = cs.map((c) => c.studentId).toList();
        for (var i = 0; i < ids.length; i++) {
          for (var j = i + 1; j < ids.length; j++) {
            final a = ids[i], b = ids[j];
            if (sec[a] != sec[b]) {
              // Waiting can never move anyone across sections.
              expect((pos[a]! < pos[b]!) == (pos2[a]! < pos2[b]!), isTrue);
              continue;
            }
            final flipped = (pos[a]! < pos[b]!) != (pos2[a]! < pos2[b]!);
            if (flipped) {
              expect((fit[a]! - fit[b]!).abs(), lessThanOrEqualTo(maxGap + 1e-9),
                  reason: 'wait-only change flipped $a/$b with fit gap ${(fit[a]! - fit[b]!).abs()}');
            }
          }
        }
      }
    });

    test('waiting 500 minutes counts the same as waiting the cap (60)', () {
      final a = engine.score(const Candidate(studentId: 'a', fit: 0.5, waitedMin: 500));
      final b = engine.score(const Candidate(studentId: 'b', fit: 0.5, waitedMin: 60));
      expect(a, equals(b));
    });

    test('waiting can lift a student past someone slightly more qualified, never far more', () {
      final ranked = engine.rank('b', const [
        Candidate(studentId: 'waited', fit: 0.70, waitedMin: 60, sent: true),
        Candidate(studentId: 'slightly-better', fit: 0.80, waitedMin: 0, sent: true),
        Candidate(studentId: 'far-better', fit: 0.95, waitedMin: 0, sent: true),
      ]);
      expect(ranked.map((x) => x.c.studentId), ['far-better', 'waited', 'slightly-better']);
    });
  });

  group('Lottery', () {
    test('ties are broken by SHA-256 of the committed seed, reproducibly', () {
      final cs = [for (var i = 0; i < 20; i++) Candidate(studentId: 's$i', fit: 0.6, waitedMin: 10, sent: true)];
      final o1 = order(cs);
      final o2 = order(cs.reversed.toList());
      expect(o1, equals(o2));
      final expected = [...cs]..sort((a, b) => FairnessEngine.sha256Hex('${settings.seed}:booth-x:${a.studentId}')
          .compareTo(FairnessEngine.sha256Hex('${settings.seed}:booth-x:${b.studentId}')));
      expect(o1, equals(expected.map((c) => c.studentId).toList()));
    });

    test('a different seed gives a different tie order (seed matters, is not ignored)', () {
      final cs = [for (var i = 0; i < 20; i++) Candidate(studentId: 's$i', fit: 0.6, waitedMin: 10, sent: true)];
      final other = FairnessEngine(const FairnessSettings(seed: 'another-seed'));
      expect(other.rank('booth-x', cs).map((r) => r.c.studentId).toList(), isNot(equals(order(cs))));
    });
  });

  group('Wait estimate', () {
    test('is a range, never a single number', () {
      final e = WaitEstimate.of(13, 3.1);
      expect(e.label, '~35 to 45 min');
      expect(e.highMin, greaterThan(e.lowMin));
    });
    test('rolling average ignores outliers and falls back to the default', () {
      expect(rollingServiceMin([], 4), 4);
      expect(rollingServiceMin([180, 5, 99999, 200], 4), closeTo(190 / 60, 1e-9));
    });
  });
}
