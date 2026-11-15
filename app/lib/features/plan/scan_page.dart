import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/platform/scanner.dart';
import '../../core/widgets/states.dart';

/// Scans a booth QR (join line / drop resume) or a friend's code.
/// In Demo Mode the booth list below lets you tap a booth instead.
class ScanPage extends ConsumerStatefulWidget {
  const ScanPage({super.key});
  @override
  ConsumerState<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends ConsumerState<ScanPage> {
  Json? fair;

  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).get('/api/fair').then((f) {
      if (mounted) setState(() => fair = f);
    });
  }

  Future<void> _handle(String code) async {
    final api = ref.read(apiProvider);
    final uri = Uri.tryParse(code);
    if (uri != null && uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'join') {
      final t = uri.queryParameters['t'];
      context.pushReplacement('/join/${uri.pathSegments[1]}${t == null ? '' : '?t=$t'}');
      return;
    }
    if (code.startsWith('qq:f:')) {
      try {
        final r = await api.post('/api/me/friends', {'code': code});
        if (mounted) {
          toast(context, 'Added ${(r['friend'] as Json)['name']} as a friend.');
          context.pop();
        }
      } on ApiException catch (e) {
        if (mounted) toast(context, e.message);
      }
      return;
    }
    if (code.startsWith('qq:s:')) {
      toast(context, 'That is a student card. Recruiters scan it from their booth screen.');
      return;
    }
    toast(context, 'Not a QueueCue booth code.');
  }

  @override
  Widget build(BuildContext context) {
    final demo = fair?['demo_mode'] == true;
    final booths = ((fair?['booths'] as List?) ?? []).cast<Json>();
    return Scaffold(
      appBar: AppBar(leading: const BackOrHome(), title: const Text('Scan booth QR')),
      body: Column(children: [
        Expanded(flex: 3, child: QrScannerView(hint: 'Point at the QR code on the booth sign', onCode: _handle)),
        if (demo)
          Expanded(
            flex: 2,
            child: ListView(padding: const EdgeInsets.all(T.gutter), children: [
              const Text('Demo Mode: tap a booth instead of scanning', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: T.s2),
              for (final b in booths)
                ListTile(
                  dense: true,
                  title: Text('${b['number']}. ${b['name']}'),
                  subtitle: Text('${b['line']} in line · ${(b['estimate'] as Json)['label']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.pushReplacement('/b/${b['id']}'),
                ),
            ]),
          ),
      ]),
    );
  }
}
