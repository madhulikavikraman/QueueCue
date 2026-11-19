import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';

/// Plain-language intro. Shown once per student, reopenable from Me.
Future<void> showHowItWorks(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(T.gutter, 0, T.gutter, T.s4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('How QueueCue works', style: Theme.of(c).textTheme.headlineSmall),
            const SizedBox(height: T.s3),
            for (final (icon, title, body) in const [
              (Icons.map_outlined, 'Map', 'Your best tents, in walking order from the entrance. Tap a tent to open it.'),
              (Icons.how_to_reg, 'Join line', 'Wait from your phone. You see how many are ahead and a time range. One line at a time.'),
              (Icons.send_outlined, 'Drop and go', 'No time to wait? Send the resume matched to that booth straight to the recruiter.'),
              (Icons.badge_outlined, 'Send my card', 'When you are talking to a recruiter, tap it. They tap Accept, and your cards swap on both phones.'),
              (Icons.verified_outlined, 'Fair Play', 'When the fair closes, your best resume reaches your top 3 fit companies, even if you never got there.'),
              (Icons.hourglass_bottom, 'Line credit', 'If a line closes while you are in it, the recruiter still gets your resume, marked with how long you waited.'),
              (Icons.emoji_events_outlined, 'Points', 'Earned for real conversations, good questions and follow-ups. They never change what recruiters see.'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: T.s3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: T.accent, borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, color: T.ink),
                  ),
                  const SizedBox(width: T.s3),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(body, style: const TextStyle(fontSize: T.small)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: T.s2),
            FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Got it')),
          ]),
        ),
      ),
    );
