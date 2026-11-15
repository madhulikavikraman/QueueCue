import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

typedef Row = Map<String, Object?>;

/// Thin wrapper over SQLite. All timestamps are epoch milliseconds (UTC).
class Db {
  final Database raw;
  Db._(this.raw);

  static Db open(String path) {
    if (path != ':memory:') {
      Directory(p.dirname(path)).createSync(recursive: true);
    }
    final db = path == ':memory:' ? sqlite3.openInMemory() : sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA foreign_keys=ON;');
    final d = Db._(db);
    d.migrate();
    return d;
  }

  void migrate() {
    raw.execute(schemaSql);
    // Columns added after the first release; ignore "duplicate column".
    for (final sql in [
      'ALTER TABLE students ADD COLUMN number INTEGER',
      'ALTER TABLE students ADD COLUMN interests TEXT',
      'ALTER TABLE students ADD COLUMN bio TEXT',
      'ALTER TABLE booths ADD COLUMN recruiter_number INTEGER',
      'ALTER TABLE recruiter_marks ADD COLUMN tags_json TEXT',
      'ALTER TABLE students ADD COLUMN password_hash TEXT',
      'ALTER TABLE booths ADD COLUMN recruiter_title TEXT',
      'ALTER TABLE booths ADD COLUMN contact_email TEXT',
    ]) {
      try {
        raw.execute(sql);
      } catch (_) {}
    }
    raw.execute('CREATE UNIQUE INDEX IF NOT EXISTS students_number ON students(number)');
  }

  List<Row> all(String sql, [List<Object?> args = const []]) {
    final rs = raw.select(sql, args);
    return [for (final r in rs) Map<String, Object?>.from(r)];
  }

  Row? one(String sql, [List<Object?> args = const []]) {
    final r = all(sql, args);
    return r.isEmpty ? null : r.first;
  }

  Object? scalar(String sql, [List<Object?> args = const []]) {
    final r = raw.select(sql, args);
    if (r.isEmpty) return null;
    return r.first.values.first;
  }

  void exec(String sql, [List<Object?> args = const []]) =>
      raw.execute(sql, args);

  int insert(String table, Map<String, Object?> values) {
    final cols = values.keys.join(',');
    final qs = List.filled(values.length, '?').join(',');
    raw.execute('INSERT INTO $table ($cols) VALUES ($qs)', values.values.toList());
    return raw.lastInsertRowId;
  }

  void upsert(String table, Map<String, Object?> values, List<String> keys) {
    final cols = values.keys.join(',');
    final qs = List.filled(values.length, '?').join(',');
    final upd = values.keys
        .where((k) => !keys.contains(k))
        .map((k) => '$k=excluded.$k')
        .join(',');
    final conflict = keys.join(',');
    raw.execute(
        'INSERT INTO $table ($cols) VALUES ($qs) ON CONFLICT($conflict) DO '
        '${upd.isEmpty ? 'NOTHING' : 'UPDATE SET $upd'}',
        values.values.toList());
  }

  T tx<T>(T Function() body) {
    raw.execute('BEGIN');
    try {
      final r = body();
      raw.execute('COMMIT');
      return r;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }

  String? meta(String key) =>
      scalar('SELECT value FROM meta WHERE key=?', [key]) as String?;
  void setMeta(String key, String value) =>
      upsert('meta', {'key': key, 'value': value}, ['key']);

  void wipe() {
    raw.execute('PRAGMA foreign_keys=OFF;');
    for (final t in tables.reversed) {
      raw.execute('DELETE FROM $t');
    }
    raw.execute('PRAGMA foreign_keys=ON;');
  }

  static const tables = [
    'meta',
    'fairs',
    'booths',
    'students',
    'resumes',
    'voice_profiles',
    'fits',
    'queue_entries',
    'drops',
    'exchanges',
    'recruiter_marks',
    'pitches',
    'ai_jobs',
    'rolodex',
    'points',
    'badges',
    'friends',
    'fairplay_prefs',
    'access_requests',
    'student_flags',
    'summaries',
    'card_requests',
    'recruiter_peers',
  ];
}

Object? jd(Object? s) => s == null ? null : jsonDecode(s as String);
String je(Object? o) => jsonEncode(o);
int nowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

const schemaSql = '''
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);

CREATE TABLE IF NOT EXISTS fairs (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  venue TEXT,
  starts_at INTEGER NOT NULL,
  ends_at INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  seed TEXT NOT NULL,
  seed_hash TEXT NOT NULL,
  w_fit REAL NOT NULL DEFAULT 0.85,
  w_effort REAL NOT NULL DEFAULT 0.15,
  effort_cap_min INTEGER NOT NULL DEFAULT 60,
  closed_at INTEGER,
  floor_w INTEGER NOT NULL DEFAULT 12,
  floor_h INTEGER NOT NULL DEFAULT 8
);

CREATE TABLE IF NOT EXISTS booths (
  id TEXT PRIMARY KEY,
  fair_id TEXT NOT NULL REFERENCES fairs(id),
  number INTEGER NOT NULL,
  name TEXT NOT NULL,
  tagline TEXT,
  category TEXT,
  about TEXT,
  roles_json TEXT NOT NULL,
  sponsors TEXT NOT NULL DEFAULT 'unknown',
  majors_json TEXT NOT NULL,
  partial_majors_json TEXT NOT NULL DEFAULT '[]',
  citizenship_required INTEGER NOT NULL DEFAULT 0,
  x INTEGER NOT NULL,
  y INTEGER NOT NULL,
  booth_key TEXT NOT NULL,
  recruiter_name TEXT,
  recruiter_email TEXT,
  recruiter_password TEXT,
  status TEXT NOT NULL DEFAULT 'open',
  default_service_min REAL NOT NULL DEFAULT 4,
  piles_json TEXT NOT NULL DEFAULT '["Standout","Strong","Maybe","Not now"]',
  last_confirm_at INTEGER
);

CREATE TABLE IF NOT EXISTS students (
  id TEXT PRIMARY KEY,
  fair_id TEXT NOT NULL,
  token TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  linkedin TEXT,
  major TEXT NOT NULL,
  degree TEXT,
  grad_year INTEGER,
  work_auth TEXT NOT NULL,
  avatar TEXT NOT NULL DEFAULT 'fox',
  persona TEXT,
  is_sim INTEGER NOT NULL DEFAULT 0,
  checked_in_at INTEGER,
  accommodation INTEGER NOT NULL DEFAULT 0,
  leaderboard_opt_in INTEGER NOT NULL DEFAULT 0,
  voice_skipped INTEGER NOT NULL DEFAULT 0,
  onboarded INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS resumes (
  id TEXT PRIMARY KEY,
  student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  label TEXT NOT NULL,
  filename TEXT,
  pdf_path TEXT,
  text TEXT NOT NULL DEFAULT '',
  blind_text TEXT NOT NULL DEFAULT '',
  parsed_json TEXT,
  is_default INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS voice_profiles (
  student_id TEXT PRIMARY KEY REFERENCES students(id) ON DELETE CASCADE,
  transcript TEXT,
  answers_json TEXT,
  profile_json TEXT,
  edits_json TEXT NOT NULL DEFAULT '[]',
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS fits (
  student_id TEXT NOT NULL,
  booth_id TEXT NOT NULL,
  fit REAL NOT NULL,
  fit_a REAL,
  fit_b REAL,
  resume_id TEXT,
  reason TEXT,
  resume_reason TEXT,
  sponsor_flag TEXT,
  major_flag TEXT,
  citizenship_block INTEGER NOT NULL DEFAULT 0,
  eligible INTEGER NOT NULL DEFAULT 1,
  source TEXT,
  matched_roles_json TEXT,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (student_id, booth_id)
);

CREATE TABLE IF NOT EXISTS queue_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  booth_id TEXT NOT NULL,
  student_id TEXT NOT NULL,
  resume_id TEXT,
  joined_at INTEGER NOT NULL,
  left_at INTEGER,
  status TEXT NOT NULL DEFAULT 'waiting',
  est_wait_at_join REAL,
  via_qr INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS drops (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  booth_id TEXT NOT NULL,
  student_id TEXT NOT NULL,
  resume_id TEXT,
  note TEXT,
  kind TEXT NOT NULL DEFAULT 'drop',
  waited_min REAL NOT NULL DEFAULT 0,
  est_wait_min REAL NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS summaries (
  booth_id TEXT NOT NULL,
  student_id TEXT NOT NULL,
  resume_id TEXT NOT NULL,
  json TEXT NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (booth_id, student_id, resume_id)
);

CREATE TABLE IF NOT EXISTS exchanges (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  booth_id TEXT NOT NULL,
  student_id TEXT NOT NULL,
  method TEXT NOT NULL,
  confirmed_by TEXT NOT NULL,
  service_sec REAL,
  waited_min REAL NOT NULL DEFAULT 0,
  resume_id TEXT,
  asked_question INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  UNIQUE (booth_id, student_id)
);

CREATE TABLE IF NOT EXISTS recruiter_marks (
  booth_id TEXT NOT NULL,
  student_id TEXT NOT NULL,
  stars REAL,
  private_note TEXT,
  pile TEXT,
  memory_note TEXT,
  manual_rank REAL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (booth_id, student_id)
);

CREATE TABLE IF NOT EXISTS pitches (
  student_id TEXT NOT NULL,
  booth_id TEXT NOT NULL,
  json TEXT NOT NULL,
  history_json TEXT NOT NULL DEFAULT '[]',
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (student_id, booth_id)
);

CREATE TABLE IF NOT EXISTS ai_jobs (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  student_id TEXT,
  booth_id TEXT,
  status TEXT NOT NULL,
  progress INTEGER NOT NULL DEFAULT 0,
  total INTEGER NOT NULL DEFAULT 1,
  message TEXT,
  result_json TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS rolodex (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  student_id TEXT NOT NULL,
  booth_id TEXT NOT NULL,
  exchange_id INTEGER,
  note TEXT,
  note_at INTEGER,
  email_json TEXT,
  email_sent_at INTEGER,
  created_at INTEGER NOT NULL,
  UNIQUE (student_id, booth_id)
);

CREATE TABLE IF NOT EXISTS points (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  student_id TEXT NOT NULL,
  rule TEXT NOT NULL,
  points INTEGER NOT NULL,
  booth_id TEXT,
  ref TEXT,
  created_at INTEGER NOT NULL,
  award_at INTEGER NOT NULL,
  UNIQUE (student_id, rule, ref)
);

CREATE TABLE IF NOT EXISTS badges (
  student_id TEXT NOT NULL,
  badge TEXT NOT NULL,
  earned_at INTEGER NOT NULL,
  PRIMARY KEY (student_id, badge)
);

CREATE TABLE IF NOT EXISTS friends (
  student_id TEXT NOT NULL,
  friend_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (student_id, friend_id)
);

CREATE TABLE IF NOT EXISTS fairplay_prefs (
  student_id TEXT NOT NULL,
  booth_id TEXT NOT NULL,
  excluded INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (student_id, booth_id)
);

CREATE TABLE IF NOT EXISTS access_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  student_id TEXT NOT NULL,
  booth_id TEXT,
  need TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  created_at INTEGER NOT NULL,
  resolved_at INTEGER
);

CREATE TABLE IF NOT EXISTS card_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,           -- 'friend' (student -> student) or 'booth' (student -> recruiter)
  from_student TEXT NOT NULL,
  to_student TEXT,
  booth_id TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL,
  resolved_at INTEGER
);

CREATE TABLE IF NOT EXISTS recruiter_peers (
  booth_id TEXT NOT NULL,
  peer_booth_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (booth_id, peer_booth_id)
);

CREATE TABLE IF NOT EXISTS student_flags (
  student_id TEXT NOT NULL,
  flag TEXT NOT NULL,
  value TEXT,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (student_id, flag)
);
''';
