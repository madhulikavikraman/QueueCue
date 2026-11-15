import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api.dart';
import '../design/tokens.dart';

/// A desk rolodex: chrome rails, black knobs, a bar with two rings, and cards
/// that flip over the bar. Swipe or tap to flip; arrows go back and forth.
class RolodexWheel extends StatefulWidget {
  final List<Json> cards;
  final bool autoplay;
  final double height;
  const RolodexWheel({super.key, required this.cards, this.autoplay = false, this.height = 330});
  @override
  State<RolodexWheel> createState() => _RolodexWheelState();
}

class _RolodexWheelState extends State<RolodexWheel> with SingleTickerProviderStateMixin {
  late final AnimationController flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  int index = 0;
  int dir = 1; // 1 forward, -1 back
  Timer? auto;

  @override
  void initState() {
    super.initState();
    if (widget.autoplay) {
      auto = Timer.periodic(const Duration(milliseconds: 2400), (_) => _go(1));
    }
  }

  @override
  void didUpdateWidget(covariant RolodexWheel old) {
    super.didUpdateWidget(old);
    if (index >= widget.cards.length) index = 0;
  }

  @override
  void dispose() {
    auto?.cancel();
    flip.dispose();
    super.dispose();
  }

  void _go(int d) {
    final n = widget.cards.length;
    if (n < 2 || flip.isAnimating) return;
    setState(() => dir = d);
    flip.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => index = (index + d + n) % n);
      flip.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.cards.length;
    if (n == 0) {
      return SizedBox(
        height: widget.height * 0.6,
        child: CustomPaint(
          painter: _RailsPainter(empty: true),
          child: const Center(child: Text('No cards yet', style: TextStyle(color: T.muted))),
        ),
      );
    }
    final next = (index + dir + n) % n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        onTap: () => _go(1),
        onVerticalDragEnd: (d) => _go((d.primaryVelocity ?? 0) <= 0 ? 1 : -1),
        onHorizontalDragEnd: (d) => _go((d.primaryVelocity ?? 0) <= 0 ? 1 : -1),
        child: SizedBox(
          height: widget.height,
          child: LayoutBuilder(builder: (context, c) {
            final w = math.min(c.maxWidth, 420.0);
            final cardW = w * 0.72;
            final cardH = widget.height * 0.56;
            final barY = widget.height * 0.62; // the axis the cards flip over
            return Center(
              child: SizedBox(
                width: w,
                height: widget.height,
                child: CustomPaint(
                  painter: _RailsPainter(barY: barY),
                  foregroundPainter: _RingsPainter(barY: barY, cardW: cardW),
                  child: AnimatedBuilder(
                    animation: flip,
                    builder: (context, _) {
                      final t = flip.value;
                      final firstHalf = t < 0.5;
                      // First half: current card falls away; second half: next card rises.
                      final angle = firstHalf ? -dir * t * 2 * (math.pi / 2) : dir * (1 - (t - 0.5) * 2) * (math.pi / 2);
                      final shown = firstHalf ? widget.cards[index] : widget.cards[next];
                      return Stack(children: [
                        // Stack of card tops behind (depth).
                        for (var i = 3; i >= 1; i--)
                          Positioned(
                            left: (w - cardW) / 2 + i * 3,
                            right: (w - cardW) / 2 + i * 3,
                            top: barY - cardH - i * 7,
                            height: cardH,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Color.lerp(Colors.white, const Color(0xFFDCD6CB), i / 4),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFBDB5A6)),
                              ),
                            ),
                          ),
                        Positioned(
                          left: (w - cardW) / 2,
                          width: cardW,
                          top: barY - cardH,
                          height: cardH,
                          child: Transform(
                            alignment: Alignment.bottomCenter,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0022)
                              ..rotateX(angle),
                            child: _CardFace(card: shown),
                          ),
                        ),
                      ]);
                    },
                  ),
                ),
              ),
            );
          }),
        ),
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(tooltip: 'Previous card', onPressed: () => _go(-1), icon: const Icon(Icons.keyboard_arrow_left)),
        Text('${index + 1} / $n', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(tooltip: 'Next card', onPressed: () => _go(1), icon: const Icon(Icons.keyboard_arrow_right)),
      ]),
    ]);
  }
}

/// Compact business-card face for the rolodex.
class _CardFace extends StatelessWidget {
  final Json card;
  const _CardFace({required this.card});
  @override
  Widget build(BuildContext context) {
    final recruiter = card['company'] != null;
    final name = '${card['name'] ?? ''}'.toUpperCase();
    final title = recruiter
        ? '${(card['title'] as String?)?.isNotEmpty == true ? card['title'] : 'Recruiter'} at ${card['company']}'
        : '${card['bio'] ?? ''}';
    final sub = recruiter ? 'Tent ${card['booth_number'] ?? ''}' : '${card['degree'] ?? ''} ${card['major'] ?? ''}'.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: T.ink, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('NO. ${card['number'] ?? ''}',
                style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1.5, fontSize: 11, color: T.muted)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: recruiter ? T.accent : T.surfaceAlt, border: Border.all(color: T.ink, width: 1.5)),
            child: Text(recruiter ? 'RECRUITER' : 'STUDENT',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          ),
        ]),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5, color: T.ink)),
        ),
        const SizedBox(height: 2),
        Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: T.ink, height: 1.25)),
        const SizedBox(height: 2),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: T.muted)),
        const Spacer(),
        if (card['email'] != null)
          Text('${card['email']}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFA34A12), decoration: TextDecoration.underline)),
      ]),
    );
  }
}

/// Chrome loop rails, black knobs and the card stack below the bar.
class _RailsPainter extends CustomPainter {
  final double barY;
  final bool empty;
  _RailsPainter({this.barY = 0, this.empty = false});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final by = empty ? h * 0.45 : barY;
    // Floor shadow.
    canvas.drawOval(Rect.fromCenter(center: Offset(w / 2, h * 0.96), width: w * 0.85, height: h * 0.07),
        Paint()..color = const Color(0x33000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // Stack of cards below the bar.
    final stackW = w * 0.74;
    for (var i = 0; i < 7; i++) {
      final y = by + 10 + i * 5.0;
      final r = RRect.fromRectAndRadius(Rect.fromLTWH((w - stackW) / 2 - i * 0.5, y, stackW + i, h * 0.2), const Radius.circular(5));
      canvas.drawRRect(r, Paint()..color = Color.lerp(Colors.white, const Color(0xFFCFC8BA), i / 7)!);
      canvas.drawRRect(r, Paint()..color = const Color(0xFFB9B1A2)..style = PaintingStyle.stroke..strokeWidth = 1);
    }
    // Chrome loop rails on each side.
    final chrome = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF2B2B2B), Color(0xFFE8E8E8), Color(0xFF4A4A4A), Color(0xFFBDBDBD)])
          .createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (final side in [-1.0, 1.0]) {
      final cx = w / 2 + side * w * 0.43;
      final path = Path()
        ..moveTo(cx, by)
        ..cubicTo(cx + side * 22, by + h * 0.15, cx + side * 18, h * 0.86, cx - side * 6, h * 0.92)
        ..lineTo(cx - side * w * 0.12, h * 0.92);
      canvas.drawPath(path, chrome);
    }
    // Axle bar + knobs.
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.08, by - 5, w * 0.84, 10), const Radius.circular(5)),
        Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF6A6A6A), Color(0xFF111111)])
            .createShader(Rect.fromLTWH(0, by - 5, w, 10)));
    for (final side in [-1.0, 1.0]) {
      final c = Offset(w / 2 + side * w * 0.44, by);
      canvas.drawCircle(c, 22, Paint()..color = const Color(0xFF151515));
      canvas.drawCircle(c - const Offset(6, 7), 7, Paint()..color = const Color(0x55FFFFFF));
    }
  }

  @override
  bool shouldRepaint(covariant _RailsPainter old) => old.barY != barY;
}

/// The two binder rings drawn over the cards.
class _RingsPainter extends CustomPainter {
  final double barY;
  final double cardW;
  _RingsPainter({required this.barY, required this.cardW});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    for (final f in [-0.22, 0.22]) {
      final c = Offset(size.width / 2 + f * cardW, barY);
      canvas.drawArc(Rect.fromCenter(center: c, width: 18, height: 34), -math.pi * 0.95, math.pi * 1.9, false, p);
      canvas.drawCircle(c + const Offset(0, 14), 3, Paint()..color = const Color(0xFF1A1A1A));
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.barY != barY || old.cardW != cardW;
}
