import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../strings.dart';

/// Demo cover: the 3D logo drops in with a tilt and bounce, a glow pulses,
/// the tagline fades in, a loading bar fills, then it fades away.
/// Tap anywhere to skip.
class SplashOverlay extends StatefulWidget {
  final VoidCallback onDone;
  const SplashOverlay({super.key, required this.onDone});
  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> with TickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
    ..forward().whenComplete(widget.onDone);
  late final AnimationController glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    glow.dispose();
    super.dispose();
  }

  double _seg(double t, double a, double b, [Curve curve = Curves.linear]) =>
      curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: GestureDetector(
        onTap: widget.onDone,
        child: AnimatedBuilder(
          animation: Listenable.merge([c, glow]),
          builder: (context, _) {
            final t = c.value;
            final drop = _seg(t, 0.0, 0.32, Curves.elasticOut);
            final tilt = (1 - _seg(t, 0.0, 0.4, Curves.easeOutCubic)) * 0.9;
            final tagline = _seg(t, 0.38, 0.55);
            final bar = _seg(t, 0.45, 0.92, Curves.easeInOut);
            final out = _seg(t, 0.92, 1.0);
            final size = math.min(MediaQuery.of(context).size.shortestSide * 0.82, 420.0);
            return Opacity(
              opacity: 1 - out,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.25),
                    radius: 1.1,
                    colors: [Color(0xFF5A0C09), Color(0xFF1A0605)],
                  ),
                ),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Stack(alignment: Alignment.center, children: [
                      // Gold glow behind the tile.
                      Container(
                        width: size * 0.95,
                        height: size * 0.95,
                        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFC72C).withValues(alpha: 0.18 + 0.17 * glow.value * drop),
                            blurRadius: 90,
                            spreadRadius: 10,
                          ),
                        ]),
                      ),
                      Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0016)
                          ..translateByDouble(0.0, (1 - drop) * -260, 0.0, 1.0)
                          ..rotateX(tilt)
                          ..scaleByDouble(0.6 + 0.4 * drop, 0.6 + 0.4 * drop, 1.0, 1.0),
                        child: Image.asset('assets/brand/logo_3d.png', width: size, filterQuality: FilterQuality.high),
                      ),
                    ]),
                    const SizedBox(height: 28),
                    Opacity(
                      opacity: tagline,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - tagline)),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Because job hunting makes everyone want to cry.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFFFBF6EC), fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Opacity(
                      opacity: tagline,
                      child: Container(
                        width: 180,
                        height: 10,
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFFFC72C), width: 2)),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(widthFactor: bar, child: Container(color: const Color(0xFFFFC72C))),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: tagline * 0.7,
                      child: Text(bar < 1 ? 'Setting up the fair' : S.app,
                          style: const TextStyle(color: Color(0xFFFBF6EC), fontSize: 12, letterSpacing: 2)),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
      );
}
