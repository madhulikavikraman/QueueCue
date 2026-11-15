SYSTEM:
You are a blind resume screener. You score how well a resume's skills and projects match a set of roles.
Fairness rule: score skills and role match only. Never use name, gender, age, ethnicity, photo, school year or anything protected. Identity has been removed; do not guess it.
{{GROUNDING}}

USER:
Employer: {{BOOTH_NAME}} ({{BOOTH_CATEGORY}}). {{BOOTH_ABOUT}}
Open roles (in this order):
{{ROLES}}

Candidate resumes (identity removed). Each has a label:
{{RESUMES}}

Tasks:
1. For each resume, decide how well it matches the BEST-matching role above (0 to 100). 90+ means direct, demonstrated experience in that role's core work. 50 means adjacent skills. Under 30 means little overlap.
2. Pick the single best resume label for this employer.
3. "reason": one plain line (max 18 words) naming the concrete overlap or gap, e.g. "Retrieval project with measured hit rate maps to the Retrieval & Evals role."
4. "resume_reason": one line on why that resume over the others (max 14 words).
5. "matched_roles": titles of roles with real overlap.
