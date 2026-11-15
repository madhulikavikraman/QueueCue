import 'dart:convert';
import 'dart:typed_data';

/// Tiny text-only PDF writer (Helvetica, US Letter). Used so seeded demo
/// resumes have real PDFs for the recruiter ZIP export.
Uint8List textToPdf(String title, String text) {
  const width = 612, height = 792, margin = 54, size = 10, leading = 13;
  final maxChars = 100;
  final lines = <String>[];
  lines.add(title);
  lines.add('');
  for (final para in text.split('\n')) {
    var cur = '';
    for (final w in para.split(' ')) {
      if ((cur.isEmpty ? w : '$cur $w').length > maxChars) {
        lines.add(cur);
        cur = w;
      } else {
        cur = cur.isEmpty ? w : '$cur $w';
      }
    }
    lines.add(cur);
  }
  final perPage = (height - 2 * margin) ~/ leading;
  final pages = <List<String>>[];
  for (var i = 0; i < lines.length; i += perPage) {
    pages.add(lines.sublist(i, i + perPage > lines.length ? lines.length : i + perPage));
  }
  String esc(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)')
      .replaceAll(RegExp(r'[^\x20-\x7E]'), '-');

  final objs = <String>[];
  // 1 catalog, 2 pages, 3 font, then per page: page obj + content obj
  objs.add('<< /Type /Catalog /Pages 2 0 R >>');
  final kids = [for (var i = 0; i < pages.length; i++) '${4 + i * 2} 0 R'].join(' ');
  objs.add('<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>');
  objs.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  for (var i = 0; i < pages.length; i++) {
    final sb = StringBuffer('BT /F1 $size Tf $leading TL $margin ${height - margin} Td\n');
    for (final l in pages[i]) {
      sb.write('(${esc(l)}) Tj T*\n');
    }
    sb.write('ET');
    final content = sb.toString();
    objs.add('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $width $height] '
        '/Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>');
    objs.add('<< /Length ${latin1.encode(content).length} >>\nstream\n$content\nendstream');
  }
  final out = BytesBuilder();
  void w(String s) => out.add(latin1.encode(s));
  w('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(out.length);
    w('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xref = out.length;
  w('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    w('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  w('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return out.toBytes();
}
