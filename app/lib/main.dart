import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'core/api/api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  final container = ProviderContainer();
  await container.read(sessionProvider.notifier).load();
  await container.read(recruiterProvider.notifier).load();
  // A saved sign-in can point at an account that no longer exists (for example
  // after "Reset demo"). Drop it so the app opens on the welcome screen.
  final saved = container.read(sessionProvider);
  if (saved != null) {
    try {
      final check = Api(apiBase())..studentToken = saved;
      await check.get('/api/me');
    } on ApiException catch (e) {
      if (e.status == 401) await container.read(sessionProvider.notifier).set(null);
    } catch (_) {}
  }
  final q = Uri.base.queryParameters;
  // Demo convenience: /?student=demo-viktor signs in as a seeded student.
  final asDemo = q['student'];
  if (asDemo != null && asDemo.startsWith('demo-')) {
    await container.read(sessionProvider.notifier).set(asDemo);
    await container.read(recruiterProvider.notifier).set(null);
  }
  // Demo convenience: /?recruiter=bk-northwind signs in as that booth's recruiter.
  final asRec = q['recruiter'];
  if (asRec != null && asRec.startsWith('bk-')) {
    final boothId = asRec.substring(3);
    try {
      final v = await Api(apiBase()).get('/api/recruiter/$boothId?key=$asRec');
      final b = v['booth'] as Map<String, dynamic>;
      await container.read(recruiterProvider.notifier).set(
          (boothId: boothId, key: asRec, name: '${b['recruiter_name'] ?? ''}', company: '${b['name']}'));
    } catch (_) {}
  }
  // Phone frame for demos on a laptop: ?frame=iphone | android | off (remembered).
  var frame = q['frame'] ?? await Prefs.get('qq_frame') ?? '';
  if (q['frame'] != null) await Prefs.set('qq_frame', frame == 'off' ? '' : frame);
  if (frame == 'off') frame = '';
  final app = UncontrolledProviderScope(container: container, child: QueueCueApp(framed: frame.isNotEmpty, splash: q['splash'] != 'off'));
  runApp(frame.isEmpty || !kIsWeb
      ? app
      : DevicePreview(
          enabled: true,
          isToolbarVisible: false,
          defaultDevice: frame == 'android' ? Devices.android.samsungGalaxyS20 : Devices.ios.iPhone13ProMax,
          backgroundColor: const Color(0xFF1D1B16),
          builder: (_) => app,
        ));
}
