/// JSON schemas passed to Ollama's `format` field (structured output) and used
/// to validate every response. PROMPTS.md is generated from these.
class Schemas {
  static const _str = {'type': 'string'};
  static const _strArr = {
    'type': 'array',
    'items': {'type': 'string'}
  };

  static const resumeParse = {
    'type': 'object',
    'properties': {
      'skills': _strArr,
      'projects': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'name': _str,
            'what': _str,
            'detail': _str,
            'role': _str,
          },
          'required': ['name', 'what', 'detail', 'role'],
        },
      },
      'experience': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {'org': _str, 'title': _str, 'detail': _str},
          'required': ['org', 'title', 'detail'],
        },
      },
      'education': _str,
    },
    'required': ['skills', 'projects', 'experience', 'education'],
  };

  static const voiceProfile = {
    'type': 'object',
    'properties': {
      'sentence_length': _str,
      'rhythm': _str,
      'contractions': {'type': 'boolean'},
      'formality': {
        'type': 'string',
        'enum': ['casual', 'neutral', 'formal']
      },
      'phrases': _strArr,
      'self_description': _str,
      'explains_technical': {
        'type': 'string',
        'enum': ['analogy-first', 'numbers-first', 'story-first', 'decision-first']
      },
      'signature_details': _strArr,
    },
    'required': [
      'sentence_length',
      'rhythm',
      'contractions',
      'formality',
      'phrases',
      'self_description',
      'explains_technical',
      'signature_details'
    ],
  };

  static const boothFit = {
    'type': 'object',
    'properties': {
      'scores': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'resume_label': _str,
            'fit': {'type': 'integer', 'minimum': 0, 'maximum': 100},
          },
          'required': ['resume_label', 'fit'],
        },
      },
      'best_resume_label': _str,
      'reason': _str,
      'resume_reason': _str,
      'matched_roles': _strArr,
    },
    'required': ['scores', 'best_resume_label', 'reason', 'resume_reason', 'matched_roles'],
  };

  static const pitchFacts = {
    'type': 'object',
    'properties': {
      'projects': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {'name': _str, 'detail': _str, 'source': _str},
          'required': ['name', 'detail', 'source'],
        },
      },
      'connection': {
        'type': 'object',
        'properties': {'role': _str, 'why': _str},
        'required': ['role', 'why'],
      },
      'question': _str,
    },
    'required': ['projects', 'connection', 'question'],
  };

  static const pitch = {
    'type': 'object',
    'properties': {
      'pitch': _str,
      'question': _str,
      'talking_points': _strArr,
      'trace': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {'sentence': _str, 'source': _str},
          'required': ['sentence', 'source'],
        },
      },
      'project': _str,
    },
    'required': ['pitch', 'question', 'talking_points', 'trace', 'project'],
  };

  static const critic = {
    'type': 'object',
    'properties': {
      'banned_found': _strArr,
      'praise': _strArr,
      'self_praise': _strArr,
      'untraceable': _strArr,
      'punctuation_issue': {'type': 'boolean'},
      'generic_question': {'type': 'boolean'},
      'specificity': {'type': 'integer', 'minimum': 1, 'maximum': 5},
      'sounds_like_them': {'type': 'integer', 'minimum': 1, 'maximum': 5},
      'believability': {'type': 'integer', 'minimum': 1, 'maximum': 5},
      'verdict': {
        'type': 'string',
        'enum': ['pass', 'rewrite']
      },
      'fix_instructions': _str,
    },
    'required': [
      'banned_found',
      'praise',
      'self_praise',
      'untraceable',
      'punctuation_issue',
      'generic_question',
      'specificity',
      'sounds_like_them',
      'believability',
      'verdict',
      'fix_instructions'
    ],
  };

  static const dropNote = {
    'type': 'object',
    'properties': {'note': _str},
    'required': ['note'],
  };

  static const recruiterSummary = {
    'type': 'object',
    'properties': {
      'headline': _str,
      'highlights': _strArr,
      'best_role': _str,
      'fit_reason': _str,
    },
    'required': ['headline', 'highlights', 'best_role', 'fit_reason'],
  };

  static const followUp = {
    'type': 'object',
    'properties': {'subject': _str, 'body': _str},
    'required': ['subject', 'body'],
  };

  static const all = {
    'resume_parse': resumeParse,
    'voice_profile': voiceProfile,
    'booth_fit': boothFit,
    'pitch_facts': pitchFacts,
    'pitch_draft': pitch,
    'pitch_critic': critic,
    'pitch_rewrite': pitch,
    'drop_note': dropNote,
    'recruiter_summary': recruiterSummary,
    'followup_email': followUp,
  };
}

/// Minimal JSON-schema validator for the subset used above. Returns a list of
/// problems (empty = valid).
List<String> validateJson(Object? v, Map<String, Object?> schema, [String path = r'$']) {
  final errs = <String>[];
  final type = schema['type'];
  switch (type) {
    case 'object':
      if (v is! Map) return ['$path: expected object'];
      for (final k in (schema['required'] as List? ?? const [])) {
        if (!v.containsKey(k)) errs.add('$path.$k: missing');
      }
      final props = (schema['properties'] as Map?) ?? const {};
      for (final e in props.entries) {
        if (v.containsKey(e.key) && v[e.key] != null) {
          errs.addAll(validateJson(
              v[e.key], (e.value as Map).cast<String, Object?>(), '$path.${e.key}'));
        }
      }
    case 'array':
      if (v is! List) return ['$path: expected array'];
      final items = schema['items'] as Map?;
      if (items != null) {
        for (var i = 0; i < v.length; i++) {
          errs.addAll(validateJson(v[i], items.cast<String, Object?>(), '$path[$i]'));
        }
      }
    case 'string':
      if (v is! String) return ['$path: expected string'];
      final en = schema['enum'] as List?;
      if (en != null && !en.contains(v)) errs.add('$path: not one of $en');
    case 'integer' || 'number':
      if (v is! num) return ['$path: expected number'];
      final mn = schema['minimum'] as num?;
      final mx = schema['maximum'] as num?;
      if (mn != null && v < mn) errs.add('$path: below $mn');
      if (mx != null && v > mx) errs.add('$path: above $mx');
    case 'boolean':
      if (v is! bool) return ['$path: expected boolean'];
  }
  return errs;
}
