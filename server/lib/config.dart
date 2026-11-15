import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// All host settings in one place. Values come from server/config.json and can
/// be overridden with environment variables (QQ_MODEL, QQ_PORT, ...).
class Config {
  final String model;
  final String ollamaUrl;
  final int port;
  final String whisperBin;
  final String whisperModel;
  final String webRoot;
  final String dbPath;
  final String uploadsDir;
  final String organizerKey;
  final String recruiterSignupCode;
  final bool demoModeDefault;
  final bool aiLiveDefault;
  final String serverDir;

  Config({
    required this.model,
    required this.ollamaUrl,
    required this.port,
    required this.whisperBin,
    required this.whisperModel,
    required this.webRoot,
    required this.dbPath,
    required this.uploadsDir,
    required this.organizerKey,
    this.recruiterSignupCode = 'TROJANCAREERFAIR',
    required this.demoModeDefault,
    required this.aiLiveDefault,
    required this.serverDir,
  });

  String resolve(String rel) =>
      p.isAbsolute(rel) ? rel : p.normalize(p.join(serverDir, rel));

  String get promptsDir => p.join(serverDir, 'lib', 'ai', 'prompts');
  String get seedDir => p.join(serverDir, 'lib', 'seed');
  String get cachePath => p.join(serverDir, 'assets', 'demo', 'ai_cache.json');

  static String findServerDir() {
    // Works for `dart run bin/server.dart` from server/ and for the repo root.
    var dir = Directory.current.path;
    for (final c in [dir, p.join(dir, 'server')]) {
      if (File(p.join(c, 'config.json')).existsSync() &&
          File(p.join(c, 'pubspec.yaml')).existsSync()) {
        return p.normalize(c);
      }
    }
    final script = p.dirname(Platform.script.toFilePath());
    return p.normalize(p.join(script, '..'));
  }

  static Config load({String? serverDir}) {
    final dir = serverDir ?? findServerDir();
    final f = File(p.join(dir, 'config.json'));
    final j = f.existsSync()
        ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{};
    final env = Platform.environment;
    String s(String k, String envK, String def) =>
        env[envK] ?? (j[k] as String?) ?? def;
    bool b(String k, String envK, bool def) {
      final e = env[envK];
      if (e != null) return e == '1' || e.toLowerCase() == 'true';
      return (j[k] as bool?) ?? def;
    }

    return Config(
      model: s('model', 'QQ_MODEL', 'qwen3:14b'),
      ollamaUrl: s('ollama_url', 'QQ_OLLAMA_URL', 'http://127.0.0.1:11434'),
      port: int.tryParse(env['QQ_PORT'] ?? '') ?? (j['port'] as int? ?? 8080),
      whisperBin: s('whisper_bin', 'QQ_WHISPER_BIN', 'whisper-cli'),
      whisperModel:
          s('whisper_model', 'QQ_WHISPER_MODEL', '../tools/whisper/ggml-small.en.bin'),
      webRoot: s('web_root', 'QQ_WEB_ROOT', '../app/build/web'),
      dbPath: s('db_path', 'QQ_DB', 'data/queuecue.db'),
      uploadsDir: s('uploads_dir', 'QQ_UPLOADS', 'data/uploads'),
      organizerKey: s('organizer_key', 'QQ_ORG_KEY', 'org-demo-key'),
      recruiterSignupCode: s('recruiter_signup_code', 'QQ_RECRUITER_CODE', 'TROJANCAREERFAIR'),
      demoModeDefault: b('demo_mode', 'QQ_DEMO', true),
      aiLiveDefault: b('ai_live', 'QQ_AI_LIVE', false),
      serverDir: dir,
    );
  }
}
