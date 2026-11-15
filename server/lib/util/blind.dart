/// Strip identity from resume text BEFORE any model sees it for scoring.
/// Removes: name tokens, emails, phones, URLs/handles, pronouns, graduation
/// years and dates, street addresses, and photo/link markers.
String blindResume(String text, {List<String> nameTokens = const []}) {
  var t = text;
  t = t.replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '[email]');
  t = t.replaceAll(
      RegExp(r'(https?://\S+|www\.\S+|linkedin\.com/\S+|github\.com/\S+)',
          caseSensitive: false),
      '[link]');
  t = t.replaceAll(
      RegExp(r'(\+?\d{1,2}[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}'), '[phone]');
  t = t.replaceAll(
      RegExp(
          r'\b\d{1,5}\s+[A-Z][a-zA-Z]+(\s[A-Z][a-zA-Z]+)*\s(St|Street|Ave|Avenue|Blvd|Rd|Road|Dr|Drive|Way|Ln|Lane)\b\.?',
          caseSensitive: false),
      '[address]');
  // Graduation years and month-year dates reveal age / school year.
  t = t.replaceAll(
      RegExp(
          r'\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?\s+(19|20)\d{2}\b'),
      '[date]');
  t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), '[year]');
  t = t.replaceAll(
      RegExp(r'\b(he/him|she/her|they/them|he|she|him|her|his|hers)\b',
          caseSensitive: false),
      '[pronoun]');
  t = t.replaceAll(RegExp(r'\b(photo|headshot)\b', caseSensitive: false), '');
  for (final n in nameTokens) {
    final tok = n.trim();
    if (tok.length < 2) continue;
    t = t.replaceAll(
        RegExp('\\b${RegExp.escape(tok)}\\b', caseSensitive: false), '[name]');
  }
  return t.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
}
