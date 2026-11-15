import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import '../design/tokens.dart';

/// Records 16 kHz mono WAV (what whisper.cpp reads directly, no ffmpeg) and
/// returns it base64-encoded.
class VoiceRecorder extends StatefulWidget {
  final int maxSeconds;
  final String startLabel;
  final void Function(String wavBase64, int seconds) onDone;
  final void Function(String error)? onError;
  const VoiceRecorder({super.key, required this.maxSeconds, required this.onDone, this.onError, this.startLabel = 'Record'});

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> {
  final rec = AudioRecorder();
  bool recording = false;
  bool busy = false;
  int secs = 0;
  Timer? t;
  StreamSubscription<Amplitude>? ampSub;
  double level = 0; // 0..1 for the meter
  double loudest = -160; // dBFS
  bool get silent => recording && secs >= 2 && loudest < -50;

  @override
  void dispose() {
    t?.cancel();
    ampSub?.cancel();
    rec.dispose();
    super.dispose();
  }

  Future<void> start() async {
    try {
      if (!await rec.hasPermission()) {
        widget.onError?.call('Microphone permission was denied. You can type instead.');
        return;
      }
      await rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: '');
      setState(() {
        recording = true;
        secs = 0;
        level = 0;
        loudest = -160;
      });
      ampSub = rec.onAmplitudeChanged(const Duration(milliseconds: 150)).listen((a) {
        if (!mounted) return;
        setState(() {
          final db = a.current.isFinite ? a.current : -160.0;
          if (db > loudest) loudest = db;
          level = ((db + 60) / 60).clamp(0.0, 1.0);
        });
      });
      t = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => secs++);
        if (secs >= widget.maxSeconds) stop();
      });
    } catch (e) {
      widget.onError?.call('Could not start the microphone ($e). On iPhone the link must be https. You can type instead.');
    }
  }

  Future<void> stop() async {
    t?.cancel();
    ampSub?.cancel();
    if (!recording) return;
    if (secs < 2) {
      await rec.stop();
      setState(() => recording = false);
      widget.onError?.call('That was under 2 seconds. Tap Record, speak, then tap Stop.');
      return;
    }
    if (loudest < -50) {
      await rec.stop();
      setState(() => recording = false);
      widget.onError?.call('No sound reached the microphone. Check that this browser has microphone access '
          '(Mac: System Settings > Privacy & Security > Microphone), reload, and try again. You can also type instead.');
      return;
    }
    setState(() {
      recording = false;
      busy = true;
    });
    try {
      final path = await rec.stop();
      if (path == null) throw Exception('no audio');
      final bytes = (await http.get(Uri.parse(path))).bodyBytes;
      widget.onDone(base64Encode(bytes), secs);
    } catch (e) {
      widget.onError?.call('Recording failed ($e). You can type instead.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.maxSeconds - secs;
    return Row(children: [
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: recording ? T.danger : T.brand),
          onPressed: busy ? null : (recording ? stop : start),
          icon: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
          label: Text(recording ? 'Stop' : widget.startLabel),
        ),
      ),
      const SizedBox(width: T.s3),
      if (recording)
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Recording: ${secs}s (${left}s left)', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: secs / widget.maxSeconds, color: T.danger),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.graphic_eq, size: 16, color: T.muted),
              const SizedBox(width: 4),
              Expanded(child: LinearProgressIndicator(value: level, minHeight: 6, color: T.success, backgroundColor: T.surfaceAlt)),
            ]),
            if (silent)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('No sound detected. Check microphone access.', style: TextStyle(color: T.danger, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      if (busy) const Text('Uploading', style: TextStyle(color: T.muted)),
    ]);
  }
}
