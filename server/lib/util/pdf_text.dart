import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Extract text from a resume PDF.
/// 1) `pdftotext` (poppler) when installed: best quality.
/// 2) Built-in extractor: inflates content streams, applies ToUnicode CMaps,
///    reads Tj/TJ/'/" operators. Handles typical Word / Google Docs / LaTeX
///    exports. Scanned image-only PDFs return empty text (the app then asks the
///    student to paste their resume text instead).
Future<String> extractPdfText(String path) async {
  try {
    final r = await Process.run('pdftotext', ['-layout', '-enc', 'UTF-8', path, '-'],
        stdoutEncoding: utf8);
    if (r.exitCode == 0 && (r.stdout as String).trim().length > 40) {
      return _clean(r.stdout as String);
    }
  } catch (_) {}
  try {
    return _clean(PdfTextExtractor(await File(path).readAsBytes()).extract());
  } catch (_) {
    return '';
  }
}

String _clean(String s) => s
    .replaceAll('\r', '\n')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n')
    .trim();

class PdfTextExtractor {
  final Uint8List bytes;
  late final String latin;
  PdfTextExtractor(this.bytes) : latin = latin1.decode(bytes, allowInvalid: true);

  final Map<int, String> _objects = {};
  final Map<String, Map<int, String>> _fontMaps = {}; // font ref -> cmap
  final Map<String, int> _fontBytes = {}; // font ref -> code width

  String extract() {
    _indexObjects();
    final out = StringBuffer();
    // Walk pages in object order; for each page find /Contents and /Font.
    final pageRe = RegExp(r'/Type\s*/Page[^s]');
    final objIds = _objects.keys.toList()..sort();
    for (final id in objIds) {
      final body = _objects[id]!;
      if (!pageRe.hasMatch(body)) continue;
      final fonts = _pageFonts(body);
      for (final cid in _contentRefs(body)) {
        final data = _streamData(cid);
        if (data == null) continue;
        out.writeln(_runContent(data, fonts));
      }
      out.writeln();
    }
    if (out.toString().trim().isEmpty) {
      // Fallback: run every stream as content.
      for (final id in objIds) {
        final d = _streamData(id);
        if (d != null && d.contains('BT')) out.writeln(_runContent(d, const {}));
      }
    }
    return out.toString();
  }

  void _indexObjects() {
    final re = RegExp(r'(\d+)\s+\d+\s+obj\b');
    final ms = re.allMatches(latin).toList();
    for (var i = 0; i < ms.length; i++) {
      final start = ms[i].end;
      final endIdx = latin.indexOf('endobj', start);
      final end = endIdx < 0 ? latin.length : endIdx;
      _objects[int.parse(ms[i].group(1)!)] = latin.substring(start, end);
    }
    // Object streams (PDF 1.5+): expand compressed objects.
    for (final e in _objects.entries.toList()) {
      if (!e.value.contains('/ObjStm')) continue;
      final data = _streamData(e.key);
      if (data == null) continue;
      final n = int.tryParse(RegExp(r'/N\s+(\d+)').firstMatch(e.value)?.group(1) ?? '');
      final first =
          int.tryParse(RegExp(r'/First\s+(\d+)').firstMatch(e.value)?.group(1) ?? '');
      if (n == null || first == null || first > data.length) continue;
      final header = data.substring(0, first).trim().split(RegExp(r'\s+'));
      final pairs = <List<int>>[];
      for (var i = 0; i + 1 < header.length && pairs.length < n; i += 2) {
        pairs.add([int.parse(header[i]), int.parse(header[i + 1])]);
      }
      for (var i = 0; i < pairs.length; i++) {
        final s = first + pairs[i][1];
        final en = i + 1 < pairs.length ? first + pairs[i + 1][1] : data.length;
        if (s <= en && en <= data.length) {
          _objects.putIfAbsent(pairs[i][0], () => data.substring(s, en));
        }
      }
    }
  }

  String? _streamData(int id) {
    final body = _objects[id];
    if (body == null) return null;
    final si = body.indexOf('stream');
    if (si < 0) return null;
    var start = si + 6;
    if (start < body.length && body[start] == '\r') start++;
    if (start < body.length && body[start] == '\n') start++;
    final ei = body.lastIndexOf('endstream');
    if (ei < start) return null;
    final raw = latin1.encode(body.substring(start, ei));
    final dict = body.substring(0, si);
    if (dict.contains('/FlateDecode')) {
      try {
        return latin1.decode(ZLibDecoder().convert(raw), allowInvalid: true);
      } catch (_) {
        try {
          // Trailing whitespace before endstream can break zlib; trim.
          var n = raw.length;
          while (n > 0 && (raw[n - 1] == 10 || raw[n - 1] == 13)) {
            n--;
          }
          return latin1.decode(ZLibDecoder().convert(raw.sublist(0, n)),
              allowInvalid: true);
        } catch (_) {
          return null;
        }
      }
    }
    if (dict.contains('/Filter')) return null; // unsupported filter
    return latin1.decode(raw, allowInvalid: true);
  }

  List<int> _contentRefs(String page) {
    final m = RegExp(r'/Contents\s*(\[[^\]]*\]|\d+\s+\d+\s+R)').firstMatch(page);
    if (m == null) return const [];
    return RegExp(r'(\d+)\s+\d+\s+R')
        .allMatches(m.group(1)!)
        .map((x) => int.parse(x.group(1)!))
        .toList();
  }

  String _deref(String s) {
    final m = RegExp(r'^\s*(\d+)\s+\d+\s+R').firstMatch(s);
    if (m != null) return _objects[int.parse(m.group(1)!)] ?? '';
    return s;
  }

  /// Returns font resource name -> font object id key.
  Map<String, String> _pageFonts(String page) {
    var res = '';
    final rm = RegExp(r'/Resources\s*(\d+\s+\d+\s+R|<<)').firstMatch(page);
    if (rm != null) {
      res = rm.group(1)!.startsWith('<<')
          ? page.substring(rm.start)
          : _deref(rm.group(1)!);
    } else {
      // inherited from parent Pages
      final pm = RegExp(r'/Parent\s+(\d+)\s+\d+\s+R').firstMatch(page);
      if (pm != null) {
        final parent = _objects[int.parse(pm.group(1)!)] ?? '';
        final rm2 = RegExp(r'/Resources\s*(\d+\s+\d+\s+R|<<)').firstMatch(parent);
        if (rm2 != null) {
          res = rm2.group(1)!.startsWith('<<')
              ? parent.substring(rm2.start)
              : _deref(rm2.group(1)!);
        }
      }
    }
    final fm = RegExp(r'/Font\s*(\d+\s+\d+\s+R|<<)').firstMatch(res);
    if (fm == null) return const {};
    final fontDict = fm.group(1)!.startsWith('<<')
        ? _balancedDict(res, fm.start + fm.group(0)!.length - 2)
        : _deref(fm.group(1)!);
    final out = <String, String>{};
    for (final m in RegExp(r'/([A-Za-z0-9_.+-]+)\s+(\d+)\s+\d+\s+R').allMatches(fontDict)) {
      final fid = int.parse(m.group(2)!);
      final key = 'f$fid';
      out[m.group(1)!] = key;
      _loadFont(key, fid);
    }
    return out;
  }

  String _balancedDict(String s, int openIdx) {
    var depth = 0;
    for (var i = openIdx; i < s.length - 1; i++) {
      if (s[i] == '<' && s[i + 1] == '<') {
        depth++;
        i++;
      } else if (s[i] == '>' && s[i + 1] == '>') {
        depth--;
        i++;
        if (depth == 0) return s.substring(openIdx, i + 1);
      }
    }
    return s.substring(openIdx);
  }

  void _loadFont(String key, int fid) {
    if (_fontMaps.containsKey(key)) return;
    final f = _objects[fid] ?? '';
    final isType0 = f.contains('/Type0');
    _fontBytes[key] = isType0 ? 2 : 1;
    final tm = RegExp(r'/ToUnicode\s+(\d+)\s+\d+\s+R').firstMatch(f);
    final map = <int, String>{};
    if (tm != null) {
      final cm = _streamData(int.parse(tm.group(1)!));
      if (cm != null) _parseCMap(cm, map);
    }
    _fontMaps[key] = map;
  }

  void _parseCMap(String cm, Map<int, String> map) {
    String hexToStr(String h) {
      final codes = <int>[];
      for (var i = 0; i + 4 <= h.length; i += 4) {
        codes.add(int.parse(h.substring(i, i + 4), radix: 16));
      }
      if (h.length == 2) codes.add(int.parse(h, radix: 16));
      return String.fromCharCodes(codes);
    }

    for (final blk in RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(cm)) {
      for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>').allMatches(blk.group(1)!)) {
        map[int.parse(m.group(1)!, radix: 16)] = hexToStr(m.group(2)!);
      }
    }
    for (final blk in RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(cm)) {
      final body = blk.group(1)!;
      for (final m in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*(<([0-9A-Fa-f]+)>|\[([^\]]*)\])')
          .allMatches(body)) {
        final lo = int.parse(m.group(1)!, radix: 16);
        final hi = int.parse(m.group(2)!, radix: 16);
        if (hi - lo > 5000) continue;
        if (m.group(4) != null) {
          final base = m.group(4)!;
          final baseCode = int.parse(base.length > 4 ? base.substring(base.length - 4) : base, radix: 16);
          for (var c = lo; c <= hi; c++) {
            map[c] = String.fromCharCode(baseCode + (c - lo));
          }
        } else {
          final arr = RegExp(r'<([0-9A-Fa-f]+)>').allMatches(m.group(5)!).toList();
          for (var i = 0; i < arr.length && lo + i <= hi; i++) {
            map[lo + i] = hexToStr(arr[i].group(1)!);
          }
        }
      }
    }
  }

  String _runContent(String data, Map<String, String> fonts) {
    final out = StringBuffer();
    var font = '';
    final tokens = _tokenize(data);
    final stack = <Object>[];
    for (final t in tokens) {
      if (t is _Op) {
        switch (t.op) {
          case 'Tf':
            if (stack.length >= 2 && stack[stack.length - 2] is _Name) {
              font = fonts[(stack[stack.length - 2] as _Name).n] ?? '';
            }
          case 'Tj' || "'" || '"':
            if (t.op != 'Tj') out.write('\n');
            final s = stack.isNotEmpty ? stack.last : null;
            if (s is _Str) out.write(_decode(s.bytes, font));
          case 'TJ':
            final a = stack.isNotEmpty ? stack.last : null;
            if (a is List) {
              for (final e in a) {
                if (e is _Str) {
                  out.write(_decode(e.bytes, font));
                } else if (e is num && e < -180) {
                  out.write(' ');
                }
              }
            }
          case 'Td' || 'TD':
            if (stack.length >= 2) {
              final ty = stack.last;
              final tx = stack[stack.length - 2];
              if (ty is num && ty.abs() > 0.5) {
                out.write('\n');
              } else if (tx is num && tx > 0.5) {
                out.write(' ');
              }
            }
          case 'T*':
            out.write('\n');
          case 'Tm':
            out.write(' ');
          case 'ET':
            out.write(' ');
        }
        stack.clear();
      } else {
        stack.add(t);
      }
    }
    return out.toString();
  }

  String _decode(List<int> b, String font) {
    final map = _fontMaps[font];
    final width = _fontBytes[font] ?? 1;
    if (map == null || map.isEmpty) {
      if (width == 2) return '';
      return String.fromCharCodes(b.where((c) => c >= 9));
    }
    final sb = StringBuffer();
    if (width == 2) {
      for (var i = 0; i + 1 < b.length; i += 2) {
        sb.write(map[(b[i] << 8) | b[i + 1]] ?? '');
      }
    } else {
      for (final c in b) {
        sb.write(map[c] ?? String.fromCharCode(c));
      }
    }
    return sb.toString();
  }

  List<Object> _tokenize(String d) {
    final out = <Object>[];
    final arrStack = <List<Object>>[];
    void push(Object o) => arrStack.isEmpty ? out.add(o) : arrStack.last.add(o);
    var i = 0;
    final n = d.length;
    while (i < n) {
      final c = d[i];
      if (' \t\r\n\f\x00'.contains(c)) {
        i++;
      } else if (c == '%') {
        while (i < n && d[i] != '\n' && d[i] != '\r') {
          i++;
        }
      } else if (c == '(') {
        final bytes = <int>[];
        var depth = 1;
        i++;
        while (i < n && depth > 0) {
          final ch = d[i];
          if (ch == '\\' && i + 1 < n) {
            final nx = d[i + 1];
            const esc = {'n': 10, 'r': 13, 't': 9, 'b': 8, 'f': 12};
            if (esc.containsKey(nx)) {
              bytes.add(esc[nx]!);
              i += 2;
            } else if (RegExp(r'[0-7]').hasMatch(nx)) {
              var j = i + 1;
              var oct = '';
              while (j < n && oct.length < 3 && RegExp(r'[0-7]').hasMatch(d[j])) {
                oct += d[j];
                j++;
              }
              bytes.add(int.parse(oct, radix: 8) & 0xff);
              i = j;
            } else if (nx == '\n' || nx == '\r') {
              i += 2;
            } else {
              bytes.add(nx.codeUnitAt(0));
              i += 2;
            }
            continue;
          }
          if (ch == '(') depth++;
          if (ch == ')') {
            depth--;
            if (depth == 0) {
              i++;
              break;
            }
          }
          bytes.add(ch.codeUnitAt(0));
          i++;
        }
        push(_Str(bytes));
      } else if (c == '<' && i + 1 < n && d[i + 1] == '<') {
        // skip inline dict
        var depth = 0;
        while (i < n - 1) {
          if (d[i] == '<' && d[i + 1] == '<') {
            depth++;
            i += 2;
          } else if (d[i] == '>' && d[i + 1] == '>') {
            depth--;
            i += 2;
            if (depth == 0) break;
          } else {
            i++;
          }
        }
      } else if (c == '<') {
        final e = d.indexOf('>', i);
        if (e < 0) break;
        var h = d.substring(i + 1, e).replaceAll(RegExp(r'\s'), '');
        if (h.length.isOdd) h += '0';
        final bytes = <int>[];
        for (var k = 0; k + 1 < h.length; k += 2) {
          bytes.add(int.tryParse(h.substring(k, k + 2), radix: 16) ?? 0);
        }
        push(_Str(bytes));
        i = e + 1;
      } else if (c == '[') {
        arrStack.add(<Object>[]);
        i++;
      } else if (c == ']') {
        if (arrStack.isNotEmpty) {
          final a = arrStack.removeLast();
          push(a);
        }
        i++;
      } else if (c == '/') {
        var j = i + 1;
        while (j < n && !' \t\r\n\f/[]()<>{}%'.contains(d[j])) {
          j++;
        }
        push(_Name(d.substring(i + 1, j)));
        i = j;
      } else {
        var j = i;
        while (j < n && !' \t\r\n\f/[]()<>{}%'.contains(d[j])) {
          j++;
        }
        if (j == i) {
          i++;
          continue;
        }
        final w = d.substring(i, j);
        final num? v = num.tryParse(w);
        if (v != null) {
          push(v);
        } else if (w == 'BI') {
          // skip inline image
          final e = d.indexOf('EI', j);
          i = e < 0 ? n : e + 2;
          continue;
        } else {
          if (arrStack.isEmpty) out.add(_Op(w));
        }
        i = j;
      }
    }
    return out;
  }
}

class _Op {
  final String op;
  _Op(this.op);
}

class _Name {
  final String n;
  _Name(this.n);
}

class _Str {
  final List<int> bytes;
  _Str(this.bytes);
}
