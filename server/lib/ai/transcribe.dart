import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Local speech-to-text with whisper.cpp. The web app records 16 kHz mono WAV,
/// which whisper.cpp reads directly (no ffmpeg needed).
class Transcriber {
  final String bin;
  final String model;
  Transcriber(this.bin, this.model);

  Future<bool> available() async {
    if (!File(model).existsSync()) return false;
    try {
      final r = await Process.run(bin, ['--help']);
      return r.exitCode == 0 || (r.stdout as String).contains('usage') || (r.stderr as String).contains('usage');
    } catch (_) {
      return false;
    }
  }

  /// Returns the transcript or throws with a readable reason.
  Future<String> transcribe(String wavPath) async {
    if (!File(model).existsSync()) {
      throw StateError('whisper model not found at $model');
    }
    final outBase = p.join(p.dirname(wavPath), p.basenameWithoutExtension(wavPath));
    final input = await _to16k(wavPath, '$outBase.16k.wav');
    final stats = wavStats(input);
    if (stats != null && (stats.seconds < 1.5 || stats.peak < 0.01) && input != wavPath) {
      try {
        File(input).deleteSync();
      } catch (_) {}
    }
    if (stats != null) {
      if (stats.seconds < 1.5) {
        _keepFailed(wavPath);
        throw AudioProblem('The recording was only ${stats.seconds.toStringAsFixed(1)} s long. Hold Record, speak, then tap Stop.');
      }
      if (stats.peak < 0.01) {
        _keepFailed(wavPath);
        throw AudioProblem('The recording was silent (${stats.seconds.round()} s, no sound). Your browser may not have microphone access: '
            'on a Mac check System Settings > Privacy & Security > Microphone for your browser, then reload the page.');
      }
    }
    final r = await Process.run(bin, [
      '-m', model, '-f', input, '-nt', '-otxt', '-of', outBase, '-l', 'en',
      '-t', '${Platform.numberOfProcessors.clamp(2, 8)}',
      '--prompt', 'A student describing a project, a career fair conversation, or a recruiter follow-up.',
    ]);
    if (input != wavPath) {
      try {
        File(input).deleteSync();
      } catch (_) {}
    }
    if (r.exitCode != 0) {
      throw StateError('whisper.cpp failed: ${(r.stderr as String).split('\n').take(2).join(' ')}');
    }
    final f = File('$outBase.txt');
    final t = f.existsSync() ? f.readAsStringSync() : (r.stdout as String);
    if (f.existsSync()) f.deleteSync();
    final clean = t
        .replaceAll(RegExp(r'\[(BLANK_AUDIO|MUSIC|NOISE|SILENCE|inaudible)[^\]]*\]', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\((music|silence|inaudible)[^)]*\)', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) {
      _keepFailed(wavPath);
      throw AudioProblem(stats != null && stats.peak < 0.05
          ? 'The recording was very quiet and no words were recognized. Move closer to the mic and try again.'
          : 'No words were recognized in the recording. Try again, speaking a little slower.');
    }
    return clean;
  }

  /// Browsers sometimes record at 44.1/48 kHz even when asked for 16 kHz.
  /// whisper.cpp needs 16 kHz mono, so convert with afconvert (macOS) or ffmpeg.
  Future<String> _to16k(String inPath, String outPath) async {
    for (final cmd in [
      ['afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', inPath, outPath],
      ['ffmpeg', '-y', '-loglevel', 'error', '-i', inPath, '-ar', '16000', '-ac', '1', outPath],
    ]) {
      try {
        final r = await Process.run(cmd.first, cmd.sublist(1));
        if (r.exitCode == 0 && File(outPath).existsSync()) return outPath;
      } catch (_) {}
    }
    return inPath;
  }

  /// Privacy: voices are never stored. The recording and any converted copy
  /// are deleted whether transcription succeeds or fails; only text remains.
  void _keepFailed(String wavPath) {}
}

class AudioProblem implements Exception {
  final String message;
  AudioProblem(this.message);
  @override
  String toString() => message;
}

/// Duration and peak level (0..1) of a 16-bit PCM WAV; null if unreadable.
({double seconds, double peak})? wavStats(String path) {
  try {
    final b = File(path).readAsBytesSync();
    if (b.length < 44 || String.fromCharCodes(b.sublist(0, 4)) != 'RIFF') return null;
    final bd = ByteData.sublistView(b);
    var off = 12;
    int channels = 1, rate = 16000, bits = 16;
    while (off + 8 <= b.length) {
      final id = String.fromCharCodes(b.sublist(off, off + 4));
      final size = bd.getUint32(off + 4, Endian.little);
      if (id == 'fmt ') {
        channels = bd.getUint16(off + 10, Endian.little);
        rate = bd.getUint32(off + 12, Endian.little);
        bits = bd.getUint16(off + 22, Endian.little);
      } else if (id == 'data') {
        if (bits != 16) return null;
        final end = (off + 8 + size).clamp(0, b.length);
        var peak = 0;
        for (var i = off + 8; i + 1 < end; i += 2) {
          final v = bd.getInt16(i, Endian.little).abs();
          if (v > peak) peak = v;
        }
        final samples = (end - off - 8) ~/ 2 ~/ channels;
        return (seconds: samples / rate, peak: peak / 32768.0);
      }
      off += 8 + size + (size.isOdd ? 1 : 0);
    }
  } catch (_) {}
  return null;
}
