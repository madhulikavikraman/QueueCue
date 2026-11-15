import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/live_builder.dart';

/// First screen: the outdoor fair as a 2.5D (isometric) pixel map of tents in
/// a line, colored by fit, with your optimal walking route.
class MapTab extends ConsumerWidget {
  const MapTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => LiveBuilder(
        fetch: (api) async => {'route': await api.get('/api/me/route'), 'me': await api.get('/api/me')},
        listen: (t) => t.startsWith('booth:') || t.startsWith('student:') || t == 'fair',
        fallbackPoll: const Duration(seconds: 15),
        builder: (context, d, reload) {
          final r = d['route'] as Json;
          final me = d['me'] as Json;
          final tents = ((r['tents'] as List?) ?? []).cast<Json>();
          final stops = ((r['stops'] as List?) ?? []).cast<Json>();
          return PageBody(onRefresh: reload, padding: const EdgeInsets.fromLTRB(0, T.s2, 0, T.s6), maxWidth: 900, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.gutter),
              child: Row(children: [
                PixelAvatar(me['avatar'] as String, size: 36),
                const SizedBox(width: T.s3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Fair map', style: Theme.of(context).textTheme.headlineSmall),
                    Text('Trousdale Parkway · ${tents.length} tents in a line', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
            ),
            if (me['onboarded'] != true)
              Padding(
                padding: const EdgeInsets.fromLTRB(T.gutter, T.s3, T.gutter, 0),
                child: Banner2(
                  text: 'Your setup is not finished, so fit scores and pitches are missing.',
                  color: T.warning,
                  bg: T.warningBg,
                  icon: Icons.hourglass_bottom,
                  action: TextButton(onPressed: () => context.go('/onboarding'), child: const Text('Finish setting up')),
                ),
              ),
            const SizedBox(height: T.s3),
            FairMap(tents: tents, stops: stops, avatar: me['avatar'] as String, onTap: (id) => context.push('/b/$id')),
            const SizedBox(height: T.s2),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: T.gutter),
              child: Wrap(spacing: T.s3, runSpacing: T.s1, children: [
                _Legend(T.success, 'high fit'),
                _Legend(T.warning, 'medium'),
                _Legend(T.danger, 'low'),
                _Legend(Color(0xFF8A8478), "can't hire you"),
                _Legend(T.brand, 'your route', dot: true),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.gutter),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SectionTitle('Your route', sub: r['explain'] as String?),
                if (stops.isEmpty)
                  const Text('No stops yet: your fit scores are still loading, or you have met everyone worth meeting.',
                      style: TextStyle(color: T.muted))
                else ...[
                  Card(
                    color: T.ink,
                    child: Padding(
                      padding: const EdgeInsets.all(T.s4),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                        _Stat('${stops.length}', 'stops'),
                        _Stat('${r['walk_meters']} m', 'walk'),
                        _Stat('~${r['wait_min']} min', 'in lines'),
                        _Stat('~${r['total_min']} min', 'total'),
                      ]),
                    ),
                  ),
                  const SizedBox(height: T.s3),
                  for (final s in stops)
                    Padding(
                      padding: const EdgeInsets.only(bottom: T.s2),
                      child: Card(
                        child: ListTile(
                          onTap: () => context.push('/b/${(s['booth'] as Json)['id']}'),
                          leading: CircleAvatar(
                            backgroundColor: T.brand,
                            child: Text('${s['step']}', style: const TextStyle(color: T.onBrand, fontWeight: FontWeight.w900)),
                          ),
                          title: Text('Tent ${(s['booth'] as Json)['number']} · ${(s['booth'] as Json)['name']}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('Fit ${s['fit_pct']} · ${s['wait_label']} · bring your ${s['resume_label']} resume'),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                    ),
                ],
              ]),
            ),
          ]);
        },
      );
}

class _Legend extends StatelessWidget {
  final Color c;
  final String label;
  final bool dot;
  const _Legend(this.c, this.label, {this.dot = false});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: dot ? BoxShape.circle : BoxShape.rectangle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: T.tiny)),
      ]);
}

class _Stat extends StatelessWidget {
  final String v;
  final String l;
  const _Stat(this.v, this.l);
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(v, style: const TextStyle(color: T.accent, fontSize: 18, fontWeight: FontWeight.w900)),
        Text(l, style: const TextStyle(color: T.bg, fontSize: T.tiny)),
      ]);
}

/// Isometric pixel map. Tents sit on one side of a straight walkway.
class FairMap extends StatelessWidget {
  final List<Json> tents;
  final List<Json> stops;
  final String avatar;
  final void Function(String boothId) onTap;
  const FairMap({super.key, required this.tents, required this.stops, required this.avatar, required this.onTap});

  static const tw = 76.0; // iso tile width
  static const th = 38.0; // iso tile height

  @override
  Widget build(BuildContext context) {
    final n = tents.isEmpty ? 12 : tents.map((t) => (t['booth'] as Json)['x'] as int).reduce(math.max);
    final width = (n + 4.4) * tw / 2 + 2.6 * tw;
    final height = (n + 3) * th / 2 + 3.2 * th;
    final geo = _IsoGeo(origin: Offset(2.2 * tw, 2.4 * th));
    final scene = GestureDetector(
      onTapUp: (e) {
        // Nearest tent within reach of the tap (scene coordinates).
        Json? best;
        var bestD = 60.0;
        for (final t in tents) {
          final p = geo.p(((t['booth'] as Json)['x'] as num).toDouble(), 0) - const Offset(0, th * 0.9);
          final dd = (p - e.localPosition).distance;
          if (dd < bestD) {
            bestD = dd;
            best = t;
          }
        }
        if (best != null) onTap((best['booth'] as Json)['id'] as String);
      },
      child: CustomPaint(
        size: Size(width, height),
        painter: _MapPainter(tents: tents, stops: stops, geo: geo, avatarColor: T.avatarColors[avatar] ?? T.brand),
      ),
    );
    // Whole line of tents fits the screen; pinch to zoom, drag to pan.
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = w * height / width;
      return SizedBox(
        width: w,
        height: h,
        child: ClipRect(
          child: InteractiveViewer(
            maxScale: 4,
            child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: width, height: height, child: scene)),
          ),
        ),
      );
    });
  }
}

class _IsoGeo {
  final Offset origin;
  _IsoGeo({required this.origin});
  /// Grid (gx along the walkway, gy across it) to screen.
  Offset p(double gx, double gy) => origin + Offset((gx - gy) * FairMap.tw / 2, (gx + gy) * FairMap.th / 2);
}

class _MapPainter extends CustomPainter {
  final List<Json> tents;
  final List<Json> stops;
  final _IsoGeo geo;
  final Color avatarColor;
  _MapPainter({required this.tents, required this.stops, required this.geo, required this.avatarColor});

  static const grass = Color(0xFF7DBE5A);
  static const grassDark = Color(0xFF5FA046);
  static const path = Color(0xFFE6CFA0);
  static const pathEdge = Color(0xFFC7A86E);
  static const outline = Color(0xFF1D1B16);

  Path quad(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();

  Color fitColor(Json t) {
    if (t['eligible'] != true) return const Color(0xFF8A8478);
    final f = (t['fit'] as num).toDouble();
    if (f >= 0.7) return const Color(0xFF2E9E57);
    if (f >= 0.5) return const Color(0xFFE0A526);
    return const Color(0xFFD9483B);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = tents.isEmpty ? 12 : tents.map((t) => (t['booth'] as Json)['x'] as int).reduce(math.max);
    final line = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Ground: grass strip, checker pixels for texture.
    for (var gx = -1; gx <= n + 1; gx++) {
      for (var gy = -1; gy <= 2; gy++) {
        final a = geo.p(gx - 0.5, gy - 0.5), b = geo.p(gx + 0.5, gy - 0.5), c = geo.p(gx + 0.5, gy + 0.5), d = geo.p(gx - 0.5, gy + 0.5);
        final isPath = gy == 1;
        canvas.drawPath(quad(a, b, c, d), Paint()..color = isPath ? path : ((gx + gy).isEven ? grass : grassDark));
      }
    }
    // Walkway edges.
    canvas.drawLine(geo.p(-1.5, 0.5), geo.p(n + 1.5, 0.5), Paint()..color = pathEdge..strokeWidth = 2);
    canvas.drawLine(geo.p(-1.5, 1.5), geo.p(n + 1.5, 1.5), Paint()..color = pathEdge..strokeWidth = 2);

    // Trees across the walkway (pixel blobs) for depth.
    for (var gx = 0; gx <= n + 1; gx += 3) {
      final base = geo.p(gx + 0.5, 2.2);
      canvas.drawRect(Rect.fromCenter(center: base - const Offset(0, 6), width: 6, height: 14), Paint()..color = const Color(0xFF6B4A2B));
      canvas.drawRect(Rect.fromCenter(center: base - const Offset(0, 22), width: 26, height: 22), Paint()..color = const Color(0xFF3F8A3A));
      canvas.drawRect(Rect.fromCenter(center: base - const Offset(-4, 28), width: 14, height: 10), Paint()..color = const Color(0xFF55A84A));
    }

    // Entrance arch.
    final ent = geo.p(-0.6, 1);
    canvas.drawRect(Rect.fromLTWH(ent.dx - 30, ent.dy - 46, 6, 46), Paint()..color = const Color(0xFF990000));
    canvas.drawRect(Rect.fromLTWH(ent.dx + 24, ent.dy - 46, 6, 46), Paint()..color = const Color(0xFF990000));
    canvas.drawRect(Rect.fromLTWH(ent.dx - 34, ent.dy - 58, 68, 14), Paint()..color = const Color(0xFFFFC72C));
    _text(canvas, 'START', ent - const Offset(0, 51), 9, outline, bold: true);

    // Route along the walkway: dotted path from entrance to the last stop.
    if (stops.isNotEmpty) {
      final lastX = ((stops.last['booth'] as Json)['x'] as int).toDouble();
      final routePaint = Paint()..color = const Color(0xFF990000);
      for (var g = -0.6; g <= lastX; g += 0.22) {
        final pt = geo.p(g, 1);
        canvas.drawRect(Rect.fromCenter(center: pt, width: 6, height: 6), routePaint);
      }
      for (final s in stops) {
        final gx = ((s['booth'] as Json)['x'] as int).toDouble();
        for (var gy = 1.0; gy >= 0.45; gy -= 0.18) {
          canvas.drawRect(Rect.fromCenter(center: geo.p(gx, gy), width: 5, height: 5), routePaint);
        }
      }
    }

    // You are here (pixel person at the entrance).
    final you = geo.p(-0.2, 1.05);
    final pp = Paint()..color = avatarColor;
    canvas.drawRect(Rect.fromCenter(center: you - const Offset(0, 22), width: 12, height: 12), pp);
    canvas.drawRect(Rect.fromCenter(center: you - const Offset(0, 9), width: 10, height: 14), pp);
    canvas.drawRect(Rect.fromCenter(center: you - const Offset(0, 22), width: 12, height: 12), line..strokeWidth = 1.5);
    _bubble(canvas, 'YOU', you - const Offset(0, 40), const Color(0xFFFFC72C));

    // Tents, back to front so nearer tents overlap farther ones.
    final sorted = [...tents]..sort((a, b) => ((a['booth'] as Json)['x'] as int).compareTo((b['booth'] as Json)['x'] as int));
    final stepOf = {for (final s in stops) (s['booth'] as Json)['id']: s['step']};
    for (final t in sorted) {
      final b = t['booth'] as Json;
      final gx = (b['x'] as int).toDouble();
      final col = b['status'] == 'open' ? fitColor(t) : const Color(0xFF55504A);
      _tent(canvas, gx, col, line);
      final top = geo.p(gx, 0) - const Offset(0, FairMap.th * 1.9);
      // Number flag.
      _bubble(canvas, '${b['number']}', top - const Offset(0, 6), Colors.white);
      // Wait chip under the flag.
      final w = (t['wait_label'] as String?) ?? '';
      _text(canvas, w == 'no wait' ? 'no wait' : w.replaceAll('~', '').replaceAll(' min', 'm'), geo.p(gx, 0) + const Offset(0, 14), 8.5, outline);
      final step = stepOf[b['id']];
      if (step != null) {
        final c = top - const Offset(22, 2);
        canvas.drawCircle(c, 10, Paint()..color = const Color(0xFF990000));
        canvas.drawCircle(c, 10, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
        _text(canvas, '$step', c, 11, Colors.white, bold: true);
      }
      if (t['met'] == true) _text(canvas, '✓ met', top + const Offset(0, 16), 9, Colors.white, bold: true);
    }
  }

  void _tent(Canvas canvas, double gx, Color col, Paint line) {
    const h = FairMap.th * 0.9; // wall height
    final b = geo.p(gx + 0.36, -0.36), c = geo.p(gx + 0.36, 0.36), d = geo.p(gx - 0.36, 0.36);
    const up = Offset(0, -h);
    final left = Color.lerp(col, Colors.black, 0.25)!;
    final right = Color.lerp(col, Colors.black, 0.05)!;
    // Walls: front-left (d->c) and front-right (b->c).
    canvas.drawPath(quad(d, c, c + up, d + up), Paint()..color = left);
    canvas.drawPath(quad(c, b, b + up, c + up), Paint()..color = right);
    // Doorway.
    final door = Offset.lerp(d, c, 0.5)!;
    canvas.drawRect(Rect.fromLTWH(door.dx - 5, door.dy - 16, 10, 14), Paint()..color = const Color(0xFF2A241C));
    // Striped peaked roof.
    final apex = geo.p(gx, 0) + up * 1.9;
    final roofL = Path()
      ..moveTo((d + up).dx, (d + up).dy)
      ..lineTo((c + up).dx, (c + up).dy)
      ..lineTo(apex.dx, apex.dy)
      ..close();
    final roofR = Path()
      ..moveTo((c + up).dx, (c + up).dy)
      ..lineTo((b + up).dx, (b + up).dy)
      ..lineTo(apex.dx, apex.dy)
      ..close();
    canvas.drawPath(roofL, Paint()..color = Colors.white);
    canvas.drawPath(roofR, Paint()..color = const Color(0xFFF3ECDD));
    // Colored stripes on the roof.
    for (var i = 0; i < 3; i++) {
      final f0 = i / 3, f1 = (i + 0.5) / 3;
      final p0 = Offset.lerp(d + up, c + up, f0)!, p1 = Offset.lerp(d + up, c + up, f1)!;
      canvas.drawPath(Path()..moveTo(p0.dx, p0.dy)..lineTo(p1.dx, p1.dy)..lineTo(apex.dx, apex.dy)..close(), Paint()..color = col);
      final q0 = Offset.lerp(c + up, b + up, f0)!, q1 = Offset.lerp(c + up, b + up, f1)!;
      canvas.drawPath(Path()..moveTo(q0.dx, q0.dy)..lineTo(q1.dx, q1.dy)..lineTo(apex.dx, apex.dy)..close(), Paint()..color = right);
    }
    final ol = Paint()
      ..color = const Color(0xFF1D1B16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawPath(quad(d, c, c + up, d + up), ol);
    canvas.drawPath(quad(c, b, b + up, c + up), ol);
    canvas.drawPath(roofL, ol);
    canvas.drawPath(roofR, ol);
    // Little flag pole on the apex.
    canvas.drawLine(apex, apex - const Offset(0, 6), ol);
  }

  void _bubble(Canvas canvas, String s, Offset center, Color bg) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF1D1B16))),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = Rect.fromCenter(center: center, width: tp.width + 10, height: tp.height + 4);
    canvas.drawRect(r, Paint()..color = bg);
    canvas.drawRect(r, Paint()..color = const Color(0xFF1D1B16)..style = PaintingStyle.stroke..strokeWidth = 1.6);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  void _text(Canvas canvas, String s, Offset center, double size, Color color, {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.tents != tents || old.stops != stops;
}
