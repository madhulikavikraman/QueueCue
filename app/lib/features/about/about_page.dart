import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/strings.dart';
import '../../core/widgets/common.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: const BackOrHome(), title: const Text(S.about)),
        body: PageBody(children: [
          const SizedBox(height: T.s4),
          Text(S.tagline, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: T.s4),
          const Text(
            'At campus career fairs, popular booths have 2+ hour lines, students print many copies of the same resume, '
            'many scan a booth QR code and leave without reaching a recruiter, and almost nobody prepares a company-specific pitch. '
            'Recruiters get a pile of paper and no way to find the best fits.',
          ),
          const SectionTitle('How QueueCue keeps it fair'),
          const Text(
            '• Lines are strict first-in, first-out. Nobody skips anyone.\n'
            '• Recruiters see people they met first, then people who waited, then resumes. Within each group: 0.85 x Fit + 0.15 x capped waiting time.\n'
            '• Fit is scored blind: names, contact details, pronouns, years and links are removed first.\n'
            '• Ties are broken by a lottery whose seed is committed at the start and revealed at close.\n'
            '• Points, levels, badges and arrival time never affect what recruiters see.\n'
            '• At close, every checked-in student\'s best resume reaches their top 3 fit companies.',
          ),
          const SectionTitle('Privacy'),
          const Text(
            'Everything runs on one laptop at the fair: the AI model, speech-to-text, the database and this app. '
            'No cloud accounts, no API keys. Voice recordings are transcribed and then deleted.',
          ),
        ]),
      );
}
