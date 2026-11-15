import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api.dart';
import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/states.dart';

/// One button: sends my booth location and need to organizer staff.
Future<void> showAccessDialog(BuildContext context, WidgetRef ref, {String? boothId, String? boothName}) async {
  final c = TextEditingController();
  final need = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(S.accessHelp),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(boothName == null ? 'Location: help desk' : 'Location: $boothName', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: T.s2),
          const Text(S.accessBody, style: TextStyle(fontSize: T.small, color: T.muted)),
          const SizedBox(height: T.s3),
          Wrap(spacing: T.s2, runSpacing: T.s2, children: [
            for (final q in ['Seat while I wait', 'Wheelchair access', 'Quiet space', 'ASL interpreter', 'Video call with recruiter'])
              ActionChip(label: Text(q), onPressed: () => c.text = q),
          ]),
          const SizedBox(height: T.s3),
          TextField(controller: c, decoration: const InputDecoration(labelText: 'What do you need?')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Send to staff')),
      ],
    ),
  );
  if (need == null) return;
  try {
    final r = await ref.read(apiProvider).post('/api/me/access', {'booth_id': boothId, 'need': need});
    if (context.mounted) toast(context, r['message'] as String);
  } on ApiException catch (e) {
    if (context.mounted) toast(context, e.message);
  }
}
