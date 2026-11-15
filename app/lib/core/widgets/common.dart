import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/live.dart';
import '../design/tokens.dart';

/// Centered, max-width page body with the standard gutter.
class PageBody extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets padding;
  final Future<void> Function()? onRefresh;
  const PageBody(
      {super.key,
      required this.children,
      this.maxWidth = T.maxContent,
      this.padding = const EdgeInsets.fromLTRB(T.gutter, T.s2, T.gutter, T.s6),
      this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: padding,
      children: [
        for (final c in children)
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: SizedBox(width: double.infinity, child: c),
            ),
          ),
      ],
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

/// One primary action per screen, at the bottom, within thumb reach.
class BottomAction extends StatelessWidget {
  final Widget child;
  final Widget? secondary;
  final Widget? above;
  const BottomAction({super.key, required this.child, this.secondary, this.above});
  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(color: T.surface, border: Border(top: BorderSide(color: T.line))),
          padding: const EdgeInsets.fromLTRB(T.gutter, T.s3, T.gutter, T.s3),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: T.maxContent),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (above != null) ...[above!, const SizedBox(height: T.s2)],
                child,
                if (secondary != null) ...[const SizedBox(height: T.s2), secondary!],
              ]),
            ),
          ),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final String? sub;
  const SectionTitle(this.text, {super.key, this.trailing, this.sub});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: T.s5, bottom: T.s2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text, style: Theme.of(context).textTheme.titleLarge),
              if (sub != null) Text(sub!, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// AI output is a result card with a source line, never a chat bubble.
class ResultCard extends StatelessWidget {
  final String title;
  final String source;
  final Widget child;
  final List<Widget> actions;
  final String? notice;
  const ResultCard({super.key, required this.title, required this.source, required this.child, this.actions = const [], this.notice});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_awesome_outlined, size: 18, color: T.brand),
              const SizedBox(width: T.s2),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: T.s1),
            Text(source, style: const TextStyle(fontSize: T.tiny, color: T.muted)),
            if (notice != null) ...[
              const SizedBox(height: T.s2),
              Banner2(text: notice!, color: T.warning, bg: T.warningBg, icon: Icons.info_outline),
            ],
            const SizedBox(height: T.s3),
            child,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: T.s3),
              Wrap(spacing: T.s2, runSpacing: T.s2, children: actions),
            ],
          ]),
        ),
      );
}

class Banner2 extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;
  final IconData icon;
  final Widget? action;
  const Banner2({super.key, required this.text, this.color = T.info, this.bg = T.infoBg, this.icon = Icons.info_outline, this.action});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(T.s3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(T.radius)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: T.s2),
          Expanded(child: Text(text, style: TextStyle(color: T.ink, fontSize: T.small))),
          if (action != null) action!,
        ]),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;
  const Pill(this.text, {super.key, this.fg = T.ink, this.bg = T.surfaceAlt, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: T.s2, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Flexible(child: Text(text, style: TextStyle(color: fg, fontSize: T.tiny, fontWeight: FontWeight.w600))),
        ]),
      );
}

class FitChip extends StatelessWidget {
  final num? fit;
  final bool big;
  const FitChip(this.fit, {super.key, this.big = false});
  @override
  Widget build(BuildContext context) {
    final pct = fit == null ? '…' : '${(fit! * 100).round()}';
    final label = fit == null ? 'pending' : (fit! >= 0.7 ? 'high fit' : (fit! >= 0.5 ? 'medium fit' : 'low fit'));
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? T.s3 : T.s2, vertical: big ? T.s2 : 4),
      decoration: BoxDecoration(
          color: T.fitBg(fit), borderRadius: BorderRadius.circular(8), border: Border.all(color: T.fitColor(fit), width: 1.2)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(pct, style: TextStyle(fontSize: big ? 26 : 18, fontWeight: FontWeight.w800, color: T.fitColor(fit), height: 1)),
        Text(label, style: TextStyle(fontSize: 10.5, color: T.fitColor(fit), fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Pixel avatar: an 8x8 symmetric sprite generated from the avatar name.
class PixelAvatar extends StatelessWidget {
  final String avatar;
  final double size;
  final bool hidden;
  const PixelAvatar(this.avatar, {super.key, this.size = 40, this.hidden = false});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SpritePainter(hidden ? 'hidden' : avatar, hidden ? T.muted : (T.avatarColors[avatar] ?? T.brand))),
      );
}

class _SpritePainter extends CustomPainter {
  final String seed;
  final Color color;
  _SpritePainter(this.seed, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = color.withValues(alpha: 0.14);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.width * 0.18)), bg);
    var h = 2166136261;
    for (final c in seed.codeUnits) {
      h = ((h ^ c) * 16777619) & 0xffffffff;
    }
    final p = Paint()..color = color;
    final cell = size.width / 10;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 4; x++) {
        h = ((h ^ (x * 31 + y * 7)) * 16777619) & 0xffffffff;
        final on = (h >> 7) & 1 == 1 || (x == 3 && (y == 2 || y == 5));
        if (!on) continue;
        for (final xx in [x, 7 - x]) {
          canvas.drawRect(Rect.fromLTWH(cell * (xx + 1), cell * (y + 1), cell + 0.5, cell + 0.5), p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) => old.seed != seed || old.color != color;
}

/// Small pixel badge for achievements.
class PixelBadge extends StatelessWidget {
  final String id;
  final bool earned;
  final double size;
  const PixelBadge(this.id, {super.key, required this.earned, this.size = 44});
  static const _icons = {
    'first_handshake': Icons.handshake_outlined,
    'paperless': Icons.eco_outlined,
    'early_bird': Icons.wb_twilight_outlined,
    'off_beaten': Icons.alt_route_outlined,
    'follow_through': Icons.mark_email_read_outlined,
    'full_house': Icons.workspace_premium_outlined,
  };
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: earned ? T.accent : T.surfaceAlt,
          border: Border.all(color: earned ? T.ink : T.line, width: 2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(_icons[id] ?? Icons.star_outline, color: earned ? T.ink : T.muted, size: size * 0.55),
      );
}

/// The queue as blocks: everyone ahead, then you.
class QueueBlocks extends StatelessWidget {
  final int ahead;
  final bool includeMe;
  const QueueBlocks({super.key, required this.ahead, this.includeMe = true});
  @override
  Widget build(BuildContext context) {
    final shown = ahead.clamp(0, 30);
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (var i = 0; i < shown; i++)
        Container(width: 14, height: 14, decoration: BoxDecoration(color: T.muted.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(2))),
      if (ahead > 30) Text('+${ahead - 30}', style: const TextStyle(fontSize: T.tiny, color: T.muted)),
      if (includeMe)
        Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: T.brand, borderRadius: BorderRadius.circular(2), border: Border.all(color: T.accent, width: 2))),
    ]);
  }
}

/// Watches a background AI job and shows honest progress.
class JobProgress extends ConsumerStatefulWidget {
  final String jobId;
  final void Function(Json job) onDone;
  final void Function(String message)? onError;
  final bool compact;
  const JobProgress({super.key, required this.jobId, required this.onDone, this.onError, this.compact = false});
  @override
  ConsumerState<JobProgress> createState() => _JobProgressState();
}

class _JobProgressState extends ConsumerState<JobProgress> {
  Json? job;
  Timer? t;
  StreamSubscription? sub;
  bool finished = false;

  @override
  void initState() {
    super.initState();
    _tick();
    t = Timer.periodic(const Duration(milliseconds: 900), (_) => _tick());
    sub = ref.read(liveProvider).topics.listen((ts) {
      if (ts.contains('job:${widget.jobId}')) _tick();
    });
  }

  @override
  void dispose() {
    t?.cancel();
    sub?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (finished) return;
    try {
      final j = await ref.read(apiProvider).get('/api/jobs/${widget.jobId}');
      if (!mounted) return;
      setState(() => job = j);
      if (j['status'] == 'done') {
        finished = true;
        t?.cancel();
        widget.onDone(j);
      } else if (j['status'] == 'error') {
        finished = true;
        t?.cancel();
        widget.onError?.call(j['message'] as String? ?? 'Failed');
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final j = job;
    final total = (j?['total'] as num?)?.toInt() ?? 1;
    final prog = (j?['progress'] as num?)?.toInt() ?? 0;
    final msg = j?['message'] as String? ?? 'Starting';
    if (j?['status'] == 'error') {
      return Banner2(text: msg, color: T.danger, bg: T.dangerBg, icon: Icons.error_outline);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(msg, style: TextStyle(fontSize: widget.compact ? T.small : T.body, color: T.ink)),
      const SizedBox(height: T.s2),
      LinearProgressIndicator(value: total <= 1 && prog == 0 ? null : (prog / total).clamp(0.0, 1.0), minHeight: 6, borderRadius: BorderRadius.circular(3)),
    ]);
  }
}

String hhmm(Object? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch((ms as num).toInt()).toLocal();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
}

String agoMin(Object? ms) {
  if (ms == null) return '';
  final m = ((DateTime.now().millisecondsSinceEpoch - (ms as num).toInt()) / 60000).floor();
  if (m < 1) return 'just now';
  if (m < 60) return '$m min ago';
  return '${(m / 60).floor()} h ${m % 60} min ago';
}

String pct(num? v) => v == null ? '–' : '${(v * 100).round()}';

/// Back arrow that always works: goes to the previous page, or to the start
/// screen when the page was opened directly from a link.
class BackOrHome extends StatelessWidget {
  const BackOrHome({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        },
      );
}
