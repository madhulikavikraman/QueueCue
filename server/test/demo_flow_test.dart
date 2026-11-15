import 'dart:convert';
import 'dart:io';

import 'package:queuecue_server/ai/lint.dart';
import 'package:queuecue_server/app.dart';
import 'package:queuecue_server/config.dart';
import 'package:queuecue_server/core/close_audit.dart';
import 'package:queuecue_server/core/qq.dart';
import 'package:queuecue_server/seed/seeder.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Runs the 90-second demo script against an in-memory database, through the
/// same service and HTTP handler the phones use.
void main() {
  late QQ qq;
  late Handler h;
  late Directory tmp;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('qq_test');
    final base = Config.load(serverDir: Directory.current.path);
    final cfg = Config(
      model: base.model,
      ollamaUrl: 'http://127.0.0.1:9', // unreachable on purpose: cached mode
      port: 0,
      whisperBin: 'whisper-cli-not-installed',
      whisperModel: '/nonexistent',
      webRoot: '/nonexistent',
      dbPath: ':memory:',
      uploadsDir: tmp.path,
      organizerKey: 'org-test',
      demoModeDefault: true,
      aiLiveDefault: false,
      serverDir: base.serverDir,
    );
    qq = await buildQQ(cfg, dbPath: ':memory:', seedIfEmpty: false);
    await Seeder(qq).run(sims: 90);
    h = buildHandler(qq, log: (_) {});
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<(int, Map<String, dynamic>)> call(String method, String path,
      {Map<String, String> headers = const {}, Object? body}) async {
    final res = await h(Request(method, Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json', ...headers}, body: body == null ? null : jsonEncode(body)));
    final text = await res.readAsString();
    return (res.statusCode, text.startsWith('{') ? jsonDecode(text) as Map<String, dynamic> : <String, dynamic>{});
  }

  const viktor = {'x-student-token': 'demo-viktor'};
  const hermione = {'x-student-token': 'demo-hermione'};

  test('1. Plan: "US citizens only" booth flagged; AI/ML resume chosen for the AI booth', () async {
    final (s, j) = await call('GET', '/api/me/plan', headers: viktor);
    expect(s, 200);
    final items = (j['items'] as List).cast<Map>();
    expect(items, hasLength(12), reason: 'never hide a booth');
    final halcyon = items.firstWhere((x) => x['booth']['id'] == 'halcyon');
    expect(halcyon['citizen_block'], isTrue);
    expect(halcyon['eligible'], isFalse);
    expect(halcyon['block_reasons'], contains('US citizens only'));
    final lumen = items.firstWhere((x) => x['booth']['id'] == 'lumen');
    expect(lumen['resume_label'], 'AI/ML');
    expect(items.first['eligible'], isTrue);
  });

  test('2. Join the big tech line: 13 ahead, "~35 to 45 min", pitch brief appears', () async {
    final (s, j) = await call('POST', '/api/booths/northwind/join', headers: viktor, body: {});
    expect(s, 200, reason: '$j');
    expect(j['ahead'], 13);
    expect(j['estimate']['label'], '~35 to 45 min');
    await qq.jobs.drain();
    final (_, b) = await call('GET', '/api/booths/northwind/me', headers: viktor);
    expect((b['pitch']['pitch'] as String), contains('900 milliseconds'));
  });

  test('3. "More like me" on a different student gives a different voice', () async {
    final (_, jj) = await call('POST', '/api/booths/northwind/pitch', headers: hermione, body: {'variant': 'more_like_me'});
    expect(jj['job_id'], isNotNull);
    await qq.jobs.drain();
    final (_, b) = await call('GET', '/api/booths/northwind/me', headers: hermione);
    final mp = b['pitch']['pitch'] as String;
    expect(mp, startsWith('140 pages a week'));
    final ap = qq.pitchFor('stu-viktor', 'northwind')!['pitch'] as String;
    expect(mp, isNot(equals(ap)));
  });

  test('4. Drop and go with the Production Eng resume', () async {
    final res = qq.resumes('stu-hermione').firstWhere((r) => r['label'] == 'Production Eng');
    final (s, j) = await call('POST', '/api/booths/northwind/drop', headers: hermione, body: {'resume_id': res['id'], 'note': 'line one\nline two'});
    expect(s, 200, reason: '$j');
    expect(j['message'], 'Dropped at Booth 1. The recruiter can see it now.');
    // Hermione also joins the line behind Viktor so we can watch her estimate move.
    final (_, line) = await call('POST', '/api/booths/northwind/join', headers: hermione, body: {});
    expect(line['ahead'], 14);
  });

  test('5. Recruiter view shows the drop live with a reason; stars are private', () async {
    final (s, v) = await call('GET', '/api/recruiter/northwind?key=bk-northwind');
    expect(s, 200);
    final sent = (v['sections'] as List).firstWhere((x) => x['key'] == 'sent')['items'] as List;
    final m = sent.firstWhere((c) => c['student']['id'] == 'stu-hermione');
    expect(m['reason'], isNotEmpty);
    expect(m['resume_label'], 'Production Eng');
    final (s2, _) = await call('POST', '/api/recruiter/northwind/mark/stu-hermione?key=bk-northwind', body: {'stars': 5});
    expect(s2, 200);
    expect(v['settings']['formula'], contains('0.85 x Fit'));
  });

  test('6a. A student cannot verify their own conversation', () async {
    final code = qq.codes.studentCode('stu-viktor', qq.clock());
    final (s1, _) = await call('POST', '/api/recruiter/northwind/confirm', headers: viktor, body: {'code': code});
    expect(s1, 403);
    final (s2, _) = await call('POST', '/api/recruiter/northwind/confirm?key=wrong', headers: viktor, body: {'code': code});
    expect(s2, 403);
    final (s3, _) = await call('POST', '/api/booths/northwind/join', headers: viktor, body: {});
    expect(s3, 200, reason: 'booth QR only joins a line; it never counts as a conversation');
    expect(qq.db.one("SELECT 1 FROM exchanges WHERE student_id='stu-viktor'"), isNull);
  });

  test('6b. An old screenshot of the rotating QR is rejected', () async {
    final old = qq.codes.studentCode('stu-viktor', qq.clock() - 5 * 60 * 1000);
    final (s, j) = await call('POST', '/api/recruiter/northwind/confirm?key=bk-northwind', body: {'code': old});
    expect(s, 400);
    expect(j['error'], contains('expired'));
  });

  test('6c. Recruiter scans Phone A: cards swap, A leaves the line, B moves up', () async {
    final (_, before) = await call('GET', '/api/booths/northwind/me', headers: hermione);
    final aheadBefore = before['line']['ahead'] as int;
    qq.db.exec('UPDATE booths SET last_confirm_at=NULL WHERE id=?', ['northwind']);
    final code = qq.codes.studentCode('stu-viktor', qq.clock());
    final (s, j) = await call('POST', '/api/recruiter/northwind/confirm?key=bk-northwind',
        body: {'code': code, 'pile': 'Standout', 'memory': 'serving, asked about batching'});
    expect(s, 200, reason: '$j');
    expect(j['student']['name'], 'Viktor Krum');
    final (_, a) = await call('GET', '/api/booths/northwind/me', headers: viktor);
    expect(a['line']['in_line'], isFalse);
    expect(a['met'], isNotNull);
    final (_, after) = await call('GET', '/api/booths/northwind/me', headers: hermione);
    expect(after['line']['ahead'], aheadBefore - 1);
    final (_, rolo) = await call('GET', '/api/me/rolodex', headers: viktor);
    expect((rolo['items'] as List).first['card']['company'], 'Northwind Cloud');
  });

  test('6d. Sanity limits: second confirm within 20 s asks "Group chat?"; one per booth', () async {
    final top = qq.waiting('northwind').first['student_id'] as String;
    final (s, j) = await call('POST', '/api/recruiter/northwind/confirm?key=bk-northwind', body: {'student_id': top});
    expect(s, 409);
    expect(j['needs_group'], isTrue);
    final code = qq.codes.studentCode('stu-viktor', qq.clock());
    final (s2, _) = await call('POST', '/api/recruiter/northwind/confirm?key=bk-northwind', body: {'code': code, 'group': true});
    expect(s2, 409, reason: 'one verified conversation per student per booth');
  });

  test('7. Rolodex voice note becomes a follow-up email in the student\'s voice', () async {
    final (s, j) = await call('POST', '/api/me/rolodex/northwind/note', headers: viktor, body: {'wav_base64': base64Encode(List.filled(64, 0))});
    expect(s, 200);
    await qq.jobs.drain();
    expect(qq.jobs.get(j['job_id'] as String)!['status'], 'done');
    final (_, e) = await call('POST', '/api/me/rolodex/northwind/email', headers: viktor);
    await qq.jobs.drain();
    final email = qq.jobs.get(e['job_id'] as String)!['result'] as Map;
    expect(email['body'], contains('continuous batching'));
    expect(lintText(email['body'] as String).banned, isEmpty);
    final (_, g) = await call('GET', '/api/me/game', headers: viktor);
    expect(g['points'], greaterThanOrEqualTo(30 + 5));
  });

  test('8. Close fair: line credit + Fair Play reaches top-3; recap and audit', () async {
    final (s, c) = await call('POST', '/api/organizer/close?org=org-test');
    expect(s, 200, reason: '$c');
    expect(c['seed'], isNotNull, reason: 'seed revealed at close');
    final (_, fp) = await call('GET', '/api/me/fairplay', headers: hermione);
    expect(fp['message'], 'Your resume reached 3 best-fit recruiters.');
    final delivered = (fp['delivered'] as List).map((d) => d['booth_id']).toSet();
    expect(delivered, containsAll(['orbital', 'halcyon']));
    // Hermione was still in line at Northwind: she gets line credit.
    final (_, v) = await call('GET', '/api/recruiter/northwind?key=bk-northwind');
    final waited = (v['sections'] as List).firstWhere((x) => x['key'] == 'waited')['items'] as List;
    expect(waited.any((x) => x['student']['id'] == 'stu-hermione'), isTrue);
    expect(waited.first['line_credit_label'], startsWith('Waited '));
    final met = (v['sections'] as List).firstWhere((x) => x['key'] == 'met')['items'] as List;
    expect(met.any((x) => x['student']['id'] == 'stu-viktor'), isTrue);
    final (_, recap) = await call('GET', '/api/me/recap', headers: hermione);
    expect(recap['resumes_delivered']['fair_play'], greaterThanOrEqualTo(2));
    expect((recap['suggestions'] as List), isNotEmpty);
    final a = qq.audit();
    expect(a['seed'], isNotNull);
    expect((a['arrival_rank_correlation'] as double).abs(), lessThan(0.25),
        reason: 'within-section order must not track arrival time');
    final (_, lb) = await call('GET', '/api/me/leaderboard', headers: hermione);
    expect((lb['friends'] as List).map((f) => f['name']), contains('Viktor Krum'));
  });

  test('Cards by number: friend request, accept, both see each other', () async {
    const dan = {'x-student-token': 'demo-percy'};
    // Personas start as friends from the seed; make a fresh pair.
    final (_, s1) = await call('POST', '/api/students', body: {'name': 'Lee Park', 'email': 'lee.park@example.edu', 'password': 'pw1234', 'major': 'Data Science', 'work_auth': 'citizen', 'interests': 'sports analytics', 'bio': 'Builds dashboards.'});
    final lee = {'x-student-token': s1['token'] as String};
    expect('${s1['number']}'.length, 4);
    final (st, r) = await call('POST', '/api/me/cards/request', headers: lee, body: {'number': '#3307'});
    expect(st, 200, reason: '$r');
    final (_, book) = await call('GET', '/api/me/cards', headers: dan);
    final inc = (book['incoming'] as List).first;
    expect(inc['card']['bio'], 'Builds dashboards.');
    final (st2, acc) = await call('POST', '/api/me/cards/${inc['id']}/accept', headers: dan);
    expect(st2, 200, reason: '$acc');
    final (_, leeBook) = await call('GET', '/api/me/cards', headers: lee);
    expect((leeBook['friends'] as List).map((f) => f['name']), contains('Percy Weasley'));
    final (_, danBook) = await call('GET', '/api/me/cards', headers: dan);
    expect((danBook['friends'] as List).map((f) => f['name']), contains('Lee Park'));
  });

  test('Booth card: student sends with a button, only the recruiter can accept', () async {
    qq.reopenBooth('lumen');
    qq.db.exec("UPDATE fairs SET status='open'");
    const dan = {'x-student-token': 'demo-percy'};
    final (st, _) = await call('POST', '/api/booths/lumen/card', headers: dan);
    expect(st, 200);
    final (_, v) = await call('GET', '/api/recruiter/lumen?key=bk-lumen');
    final reqs = (v['card_requests'] as List);
    expect(reqs.single['student']['name'], 'Percy Weasley');
    final id = reqs.single['id'];
    final (bad, _) = await call('POST', '/api/recruiter/lumen/requests/$id/accept', headers: dan);
    expect(bad, 403, reason: 'a student token cannot accept');
    qq.db.exec('UPDATE booths SET last_confirm_at=NULL');
    final (ok, r) = await call('POST', '/api/recruiter/lumen/requests/$id/accept?key=bk-lumen');
    expect(ok, 200, reason: '$r');
    final (_, book) = await call('GET', '/api/me/cards', headers: dan);
    expect((book['recruiters'] as List).map((c) => c['company']), contains('Lumen Labs'));
  });

  test('Recruiter can type a student number instead of scanning', () async {
    qq.db.exec('UPDATE booths SET last_confirm_at=NULL');
    final (st, r) = await call('POST', '/api/recruiter/bayside/confirm?key=bk-bayside', body: {'number': '4512'});
    expect(st, 200, reason: '$r');
    expect(r['student']['name'], 'Hermione Granger');
  });

  test('Route: best stops in walking order along the line of tents', () async {
    qq.db.exec("UPDATE fairs SET status='open'");
    qq.db.exec("UPDATE booths SET status='open'");
    final (_, r) = await call('GET', '/api/me/route', headers: {'x-student-token': 'demo-hermione'});
    final xs = (r['stops'] as List).map((s) => s['booth']['x'] as int).toList();
    expect(xs, isNotEmpty);
    expect(xs, equals([...xs]..sort()), reason: 'no backtracking');
    expect((r['stops'] as List).every((s) => s['eligible'] == true && (s['fit'] as num) >= 0.6), isTrue);
    expect((r['tents'] as List), hasLength(12));
  });

  test('Recruiters swap cards with each other by number; tags are saved', () async {
    final nw = qq.booth('northwind')['recruiter_number'];
    final (st, _) = await call('POST', '/api/recruiter/kestrel/cards/share?key=bk-kestrel', body: {'number': '$nw'});
    expect(st, 200);
    final (_, book) = await call('GET', '/api/recruiter/northwind/cards?key=bk-northwind');
    final id = (book['incoming_peers'] as List).single['id'];
    await call('POST', '/api/recruiter/northwind/peers/$id/accept?key=bk-northwind');
    final (_, kb) = await call('GET', '/api/recruiter/kestrel/cards?key=bk-kestrel');
    expect((kb['peers'] as List).map((p) => p['company']), contains('Northwind Cloud'));
    await call('POST', '/api/recruiter/northwind/mark/stu-viktor?key=bk-northwind', body: {'tags': ['Strong project', 'Great questions'], 'stars': 5});
    final (_, nb) = await call('GET', '/api/recruiter/northwind/cards?key=bk-northwind');
    final v = (nb['students'] as List).firstWhere((x) => x['name'] == 'Viktor Krum');
    expect(v['tags'], contains('Great questions'));
  });

  test('Student types a recruiter\'s card number: request goes to that booth', () async {
    final n = qq.booth('gridwise')['recruiter_number'];
    final (st, r) = await call('POST', '/api/me/cards/request', headers: {'x-student-token': 'demo-hermione'}, body: {'number': '$n'});
    expect(st, 200, reason: '$r');
    final (_, v) = await call('GET', '/api/recruiter/gridwise?key=bk-gridwise');
    expect((v['card_requests'] as List).map((x) => x['student']['name']), contains('Hermione Granger'));
  });

  test('Same email + password resumes the saved student; no duplicate', () async {
    final body = {'name': 'Neville Longbottom', 'email': 'Neville@Example.edu', 'password': 'herbology', 'major': 'Computer Science', 'work_auth': 'citizen'};
    final (_, a) = await call('POST', '/api/students', body: body);
    final (_, b) = await call('POST', '/api/students', body: {...body, 'email': 'neville@example.edu'});
    expect(b['token'], a['token']);
    expect(b['resumed'], isTrue);
    final (bad, _) = await call('POST', '/api/students', body: {...body, 'password': 'wrong'});
    expect(bad, 409);
    final (_, l) = await call('POST', '/api/students/login', body: {'email': 'neville@example.edu', 'password': 'herbology'});
    expect(l['token'], a['token']);
    final n = qq.db.scalar("SELECT COUNT(*) FROM students WHERE lower(email)='neville@example.edu'");
    expect(n, 1);
  });

  test('Recruiter sign-up needs the fair code and creates a scored tent', () async {
    final body = {'code': 'nope', 'name': 'Minerva McGonagall', 'email': 'minerva@transfig.example', 'password': 'tabby', 'company': 'Transfiguration Labs', 'role': 'ML Engineer', 'majors': ['Computer Science']};
    final (bad, _) = await call('POST', '/api/recruiter/signup', body: body);
    expect(bad, 403);
    final (ok, r) = await call('POST', '/api/recruiter/signup', body: {...body, 'code': 'trojancareerfair'});
    expect(ok, 200, reason: '$r');
    expect('${r['number']}'.length, 3);
    final (again, r2) = await call('POST', '/api/recruiter/signup', body: {...body, 'code': 'TROJANCAREERFAIR'});
    expect(again, 200);
    expect(r2['booth_id'], r['booth_id'], reason: 'signing up twice signs you back in');
    final (_, login) = await call('POST', '/api/recruiter/login', body: {'email': 'minerva@transfig.example', 'password': 'tabby'});
    expect(login['booth_id'], r['booth_id']);
    final sims = qq.db.scalar("SELECT COUNT(*) FROM fits WHERE booth_id=?", [r['booth_id']]) as int;
    expect(sims, greaterThan(50), reason: 'every student gets a fit score for the new tent');
  });

  test('Recruiter edits card; changing credentials needs the current password', () async {
    final (ok, r) = await call('POST', '/api/recruiter/ridgeway/profile?key=bk-ridgeway', body: {'title': 'Head of Campus Hiring', 'about': 'Quant research internships'});
    expect(ok, 200, reason: '$r');
    expect(r['card']['title'], 'Head of Campus Hiring');
    final (bad, _) = await call('POST', '/api/recruiter/ridgeway/profile?key=bk-ridgeway', body: {'new_password': 'gringotts', 'current_password': 'wrong'});
    expect(bad, 403);
    final (ok2, _) = await call('POST', '/api/recruiter/ridgeway/profile?key=bk-ridgeway',
        body: {'email': 'bill@gringotts.example', 'new_password': 'gringotts', 'current_password': 'ridgeway'});
    expect(ok2, 200);
    final (st, l) = await call('POST', '/api/recruiter/login', body: {'email': 'bill@gringotts.example', 'password': 'gringotts'});
    expect(st, 200);
    expect(l['booth_id'], 'ridgeway');
    final (old, _) = await call('POST', '/api/recruiter/login', body: {'email': 'bill@ridgeway.example', 'password': 'ridgeway'});
    expect(old, 401);
  });

  test('Card email is editable without a password and does not change sign-in', () async {
    final (ok, r) = await call('POST', '/api/recruiter/kestrel/profile?key=bk-kestrel', body: {'card_email': 'fred@weasleys.example'});
    expect(ok, 200, reason: '$r');
    expect(r['card']['email'], 'fred@weasleys.example');
    final (st, _) = await call('POST', '/api/recruiter/login', body: {'email': 'fred@kestrel.example', 'password': 'kestrel'});
    expect(st, 200);
  });

  test('Every cached pitch passes the deterministic critic', () {
    final cache = jsonDecode(File('assets/demo/ai_cache.json').readAsStringSync())['entries'] as Map<String, dynamic>;
    for (final e in cache.entries.where((e) => e.key.startsWith('pitch:'))) {
      final v = e.value as Map<String, dynamic>;
      final shorter = e.key.endsWith(':shorter');
      final l = lintText(v['pitch'] as String,
          question: v['question'] as String, minWords: shorter ? 35 : 50, maxWords: shorter ? 60 : 85);
      expect(l.issues, isEmpty, reason: '${e.key}: ${l.issues}');
      expect((v['talking_points'] as List), hasLength(2), reason: e.key);
    }
  });

  test('Every number in a cached pitch is traceable to the student materials', () {
    final cache = jsonDecode(File('assets/demo/ai_cache.json').readAsStringSync())['entries'] as Map<String, dynamic>;
    for (final e in cache.entries.where((e) => e.key.startsWith('pitch:'))) {
      final persona = e.key.split(':')[1];
      final ctx = qq.studentCtx('stu-$persona');
      final b = qq.boothCtx(qq.booth(e.key.split(':')[2]));
      final raw = qq.resumes('stu-$persona').map((r) => r['text'] as String).join('\n');
      final t = traceSentences((e.value as Map)['pitch'] as String, {
        'resumes': raw,
        'voice': '${ctx.transcript} ${ctx.answers.join(' ')}',
        'employer': b.asText,
      });
      for (final s in t) {
        expect(s['traceable'], isTrue, reason: '${e.key}: "${s['sentence']}" missing ${s['missing_numbers']}');
      }
    }
  });
}
