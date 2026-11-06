"""Build the functional agent's prompt from a gate analysis."""

from sfl_gate.gate import CLAUSE_MARKERS, DISCOURSE_MARKERS, Analysis


def _clause_lines(analysis: Analysis) -> list[str]:
    lines: list[str] = []
    for i, clause in enumerate(analysis.clauses, start=1):
        participants = "; ".join(f"{p.role}={p.text!r}" for p in clause.participants) or "none detected"
        circumstances = "; ".join(f"{c.type}={c.text!r}" for c in clause.circumstances) or "none detected"
        modality = "; ".join(f"{w} ({kind}, {degree})" for w, kind, degree in clause.modality) or "none"
        appraisal = ", ".join(clause.appraisal) or "none"
        lines.append(
            f"{i}. \"{clause.text}\"\n"
            f"   - Ideational: process={clause.process_type} (verb: {clause.process_verb or 'n/a'}); "
            f"participants: {participants}; circumstances: {circumstances}\n"
            f"   - Interpersonal: mood={clause.mood}; modality: {modality}; appraisal intensifiers: {appraisal}\n"
            f"   - Textual: theme={clause.theme!r}; rheme={clause.rheme!r}"
        )
    return lines


def _directives(analysis: Analysis) -> list[str]:
    directives: list[str] = []
    if analysis.field:
        directives.append(
            "Ideational: ground the reply in the subject matter (" + ", ".join(analysis.field) + ") "
            "and address every participant the gate identified by role."
        )
    else:
        directives.append("Ideational: address the content of the raw input directly.")
    directives.append(f"Interpersonal: match the input's stance ({analysis.tenor}).")
    themes = [
        c.theme
        for c in analysis.clauses
        if c.theme and c.theme.lower() not in CLAUSE_MARKERS and c.theme.lower() not in DISCOURSE_MARKERS
    ]
    if themes:
        directives.append(
            "Textual: open from the theme of the input (" + " / ".join(themes) + ") and keep the reply cohesive."
        )
    else:
        directives.append("Textual: structure the reply clearly and keep it cohesive.")
    return directives


def build_prompt(analysis: Analysis) -> str:
    """Render the deterministic gate's output as the prompt the functional agent receives."""
    parts = [
        "=== SFL GATE OUTPUT (deterministic expansion of the user's raw input) ===",
        f"RAW INPUT: {analysis.raw}",
        "",
        "REGISTER (context of situation):",
        f"- Field (subject matter): {', '.join(analysis.field) if analysis.field else 'unspecified'}",
        f"- Tenor (stance and relation): {analysis.tenor}",
        f"- Mode (channel): {analysis.mode}",
        f"- Lexical density: {analysis.lexical_density}",
        f"- Cohesive devices present: {', '.join(analysis.cohesion) if analysis.cohesion else 'none'}",
        "",
        "CLAUSE-BY-CLAUSE METAFUNCTIONAL ANNOTATION:",
        *(_clause_lines(analysis) or ["- (no clauses detected)"]),
        "",
        "TASK DIRECTIVES:",
        *(f"- {d}" for d in _directives(analysis)),
        "",
        "=== END SFL GATE OUTPUT ===",
        "Answer the user's request above. Then append a short section titled 'SFL reading' that",
        "summarizes in two or three lines which metafunctions the gate surfaced and how they",
        "shaped your answer.",
    ]
    return "\n".join(parts)
