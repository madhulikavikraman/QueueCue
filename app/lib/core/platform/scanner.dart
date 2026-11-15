import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../design/tokens.dart';

/// Full-screen QR scanner. Returns the first decoded value via [onCode].
/// Camera access needs HTTPS on iPhone (the Cloudflare tunnel link).
class QrScannerView extends StatefulWidget {
  final void Function(String code) onCode;
  final String hint;
  const QrScannerView({super.key, required this.onCode, required this.hint});
  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  final controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  bool handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: controller,
          onDetect: (cap) {
            if (handled) return;
            final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (v == null) return;
            handled = true;
            widget.onCode(v);
            Future.delayed(const Duration(seconds: 2), () => handled = false);
          },
          errorBuilder: (ctx, err) => Container(
            color: T.ink,
            padding: const EdgeInsets.all(T.s5),
            alignment: Alignment.center,
            child: Text(
              'Camera unavailable (${err.errorCode.name}). On iPhone, open the https link and allow camera access.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: T.bg),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: const EdgeInsets.all(T.s4),
            padding: const EdgeInsets.all(T.s3),
            decoration: BoxDecoration(color: T.ink.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(T.radius)),
            child: Text(widget.hint, style: const TextStyle(color: T.bg), textAlign: TextAlign.center),
          ),
        ),
        Center(
          child: Container(
            width: 230,
            height: 230,
            decoration: BoxDecoration(border: Border.all(color: T.accent, width: 3), borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ]);
}

/// Opens the scanner in a dialog (recruiter laptop / tablet) and returns the code.
Future<String?> scanQrDialog(BuildContext context, {required String hint}) => showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(T.s4),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          height: 520,
          child: Stack(children: [
            QrScannerView(hint: hint, onCode: (c) => Navigator.of(ctx).pop(c)),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton.filled(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close), tooltip: 'Close'),
            ),
          ]),
        ),
      ),
    );
