/// Deterministic half of the critic pass. Runs on EVERY pitch, note and email
/// regardless of where it came from (live model, cache, offline draft), so the
/// banned-word and traceability rules can never be skipped.
const bannedPhrases = [
  'passionate',
  'leverage',
  'synergy',
  'cutting-edge',
  'cutting edge',
  'innovative',
  'dynamic',
  'results-driven',
  'thrilled',
  'excited to',
  "i'd love to",
  'i would love to',
  "i've always been fascinated",
  'i have always been fascinated',
  'deeply',
  'unique opportunity',
  'aligns perfectly',
  'valuable',
  'world-class',
  'revolutionize',
];

final _asAStudent = RegExp(r'\bas an? [\w\s/&-]{1,40}student\b', caseSensitive: false);

const _praisePatterns = [
  'love your',
  'love the mission',
  'your mission',
  'leader in',
  'industry leader',
  'admire',
  'big fan',
  'amazing company',
  'great company',
  'impressed by your',
  'dream company',
];

const _selfPraise = [
  'strong problem solver',
  'hard worker',
  'hard-working',
  'team player',
  'fast learner',
  'quick learner',
  'detail-oriented',
  'self-starter',
  'go-getter',
];

const _genericQuestions = [
  'culture',
  'typical day',
  'day in the life',
  'what are you looking for',
  'what do you look for',
  'how can i stand out',
  'any advice',
  'what qualities',
  'tell me about the company',
  'what does your company do',
  'work-life balance',
];

final _emoji = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F000}-\u{1F2FF}\u{1F900}-\u{1F9FF}]',
    unicode: true);

class LintResult {
  final List<String> issues;
  final List<String> banned;
  final bool genericQuestion;
  final int words;
  LintResult(this.issues, this.banned, this.genericQuestion, this.words);
  bool get ok => issues.isEmpty;
  Map<String, Object?> toJson() => {
        'ok': ok,
        'issues': issues,
        'banned_found': banned,
        'generic_question': genericQuestion,
        'words': words,
      };
}

int wordCount(String s) =>
    s.trim().isEmpty ? 0 : s.trim().split(RegExp(r'\s+')).length;

List<String> findBanned(String text) {
  final t = text.toLowerCase().replaceAll('’', "'");
  final out = <String>[
    for (final b in bannedPhrases)
      if (RegExp('\\b${RegExp.escape(b)}\\b').hasMatch(t)) b
  ];
  if (_asAStudent.hasMatch(text)) out.add('"As a ___ student"');
  return out;
}

LintResult lintText(String text,
    {String? question, int? minWords, int? maxWords, String? boothName}) {
  final issues = <String>[];
  final banned = findBanned('$text ${question ?? ''}');
  if (banned.isNotEmpty) issues.add('Banned wording: ${banned.join(', ')}');
  final lower = text.toLowerCase();
  for (final p in _praisePatterns) {
    if (lower.contains(p)) issues.add('Praises the company ("$p")');
  }
  for (final p in _selfPraise) {
    if (lower.contains(p)) issues.add('Self-praise without evidence ("$p")');
  }
  final ex = '!'.allMatches('$text ${question ?? ''}').length;
  if (ex > 1) issues.add('More than one exclamation mark');
  if (_emoji.hasMatch('$text ${question ?? ''}')) issues.add('Contains emoji');
  final w = wordCount(text);
  if (minWords != null && w < minWords) issues.add('Too short ($w words, min $minWords)');
  if (maxWords != null && w > maxWords) issues.add('Too long ($w words, max $maxWords)');
  var generic = false;
  if (question != null) {
    final q = question.toLowerCase();
    generic = _genericQuestions.any(q.contains) || wordCount(question) < 6;
    if (generic) issues.add('Question is generic; it could be asked at any booth');
  }
  return LintResult(issues, banned, generic, w);
}

/// Split into sentences (keeps decimals like 2.1 intact).
List<String> sentences(String text) => text
    .replaceAll('\n', ' ')
    .split(RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9"“])'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

final _stop = {
  'the', 'a', 'an', 'and', 'or', 'to', 'of', 'in', 'on', 'for', 'with', 'i',
  'my', 'me', 'it', 'is', 'was', 'that', 'this', 'so', 'at', 'as', 'by', 'from',
  'your', 'you', 'we', 'our', 'be', 'are', 'were', 'about', 'like', 'its', "it's",
  "i'm", 'im', 'am', 'what', 'which', 'how', 'do', 'did', 'just', 'also', 'then',
  'into', 'up', 'out', 'over', 'there', 'they', 'them', 'one', 'had', 'have',
};

Set<String> _tokens(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z0-9%.\s']"), ' ')
    .split(RegExp(r'\s+'))
    .map((w) => w.replaceAll(RegExp(r"^[.']+|[.']+$"), ''))
    .where((w) => w.length > 1 && !_stop.contains(w))
    .toSet();

final _numRe = RegExp(r'\d+(?:\.\d+)?');

/// Trace each sentence to its best source. A sentence whose numbers do not
/// appear in any source is flagged untraceable (numbers are the most common
/// hallucination). Spelled-out numbers in the source are normalized.
List<Map<String, Object?>> traceSentences(
    String text, Map<String, String> sources) {
  final normSources = {
    for (final e in sources.entries) e.key: _normalizeNumbers(e.value)
  };
  final out = <Map<String, Object?>>[];
  for (final s in sentences(text)) {
    final st = _tokens(s);
    String best = 'unknown';
    var bestScore = 0.0;
    for (final e in normSources.entries) {
      final overlap = st.intersection(_tokens(e.value)).length;
      final score = st.isEmpty ? 0.0 : overlap / st.length;
      if (score > bestScore) {
        bestScore = score;
        best = e.key;
      }
    }
    final nums = _numRe.allMatches(_normalizeNumbers(s)).map((m) => m.group(0)!);
    final allText = normSources.values.join(' ');
    final missing = nums.where((n) => !allText.contains(n)).toList();
    out.add({
      'sentence': s,
      'source': bestScore >= 0.12 ? best : 'intro / connective',
      'traceable': missing.isEmpty,
      if (missing.isNotEmpty) 'missing_numbers': missing,
    });
  }
  return out;
}

const _numWords = {
  'zero': '0', 'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
  'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
  'eleven': '11', 'twelve': '12', 'fourteen': '14', 'eighteen': '18',
  'twenty': '20', 'thirty': '30', 'forty': '40', 'fifty': '50', 'sixty': '60',
  'eighty': '80', 'ninety': '90', 'hundred': '100',
  'forty-two': '42', 'fifty-three': '53', 'eighty-five': '85',
  'one hundred and twenty': '120', 'a hundred and twenty': '120',
  'one forty': '140',
};

String _normalizeNumbers(String s) {
  var t = s.toLowerCase();
  final keys = _numWords.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    t = t.replaceAll(RegExp('\\b${RegExp.escape(k)}\\b'), _numWords[k]!);
  }
  return t.replaceAllMapped(
      RegExp(r'(\d),(\d{3})'), (m) => '${m.group(1)}${m.group(2)}');
}
