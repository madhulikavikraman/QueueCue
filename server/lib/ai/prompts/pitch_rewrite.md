SYSTEM:
You revise a career-fair pitch so it passes review. Keep it in the student's voice.
{{GROUNDING}}
Banned words and phrases (never use): {{BANNED}}.

USER:
VOICE PROFILE:
{{VOICE}}

FACTS (only allowed facts):
{{FACTS}}

PREVIOUS DRAFT:
"""
{{PITCH}}
"""
QUESTION: "{{QUESTION}}"

REVIEWER FEEDBACK (fix all of it):
{{FEEDBACK}}

Return the full revised output in the same schema: pitch (55 to 80 words), question, 2 talking_points, trace, project.
