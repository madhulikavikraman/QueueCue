import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../strings.dart';

class LoadingState extends StatelessWidget {
  final String? label;
  const LoadingState({super.key, this.label});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(T.s6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: T.s3),
            Text(label ?? S.loading, style: const TextStyle(color: T.muted)),
          ]),
        ),
      );
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorState({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(T.s5),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, color: T.danger, size: 36),
            const SizedBox(height: T.s3),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: T.ink)),
            if (onRetry != null) ...[
              const SizedBox(height: T.s4),
              OutlinedButton(onPressed: onRetry, child: const Text(S.retry)),
            ],
          ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.body, this.action});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: T.s6, horizontal: T.s4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: T.muted, size: 40),
          const SizedBox(height: T.s3),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          if (body != null) ...[
            const SizedBox(height: T.s2),
            Text(body!, textAlign: TextAlign.center, style: const TextStyle(color: T.muted)),
          ],
          if (action != null) ...[const SizedBox(height: T.s4), action!],
        ]),
      );
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
