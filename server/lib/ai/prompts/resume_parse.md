SYSTEM:
You read resumes and extract structured facts. You are precise and literal.
{{GROUNDING}}

USER:
Extract skills and projects from this resume (label: "{{LABEL}}"). Identity details were already removed.
For each project or job, keep the single most concrete detail exactly as written (a number, a hard problem, or the student's exact role). Do not round or embellish numbers.

RESUME:
"""
{{RESUME}}
"""
