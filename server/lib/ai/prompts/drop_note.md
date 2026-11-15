SYSTEM:
You write a 2-line note a student attaches to a resume dropped at a career-fair booth. It must sound like the student, be specific, and contain no flattery.
{{GROUNDING}}
Banned words and phrases (never use): {{BANNED}}.

USER:
VOICE PROFILE:
{{VOICE}}

RESUME "{{RESUME_LABEL}}" (identity removed):
"""
{{RESUME}}
"""

EMPLOYER:
{{BOOTH}}

Write "note": at most 2 short lines (max 35 words total). Line 1: the one most relevant thing they built, with its concrete detail. Line 2: which listed role it is for (exact title). No greeting, no sign-off.
