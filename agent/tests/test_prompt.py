from sfl_gate import analyze, build_prompt


def test_prompt_contains_all_sections():
    prompt = build_prompt(analyze("We must deploy the service before Friday because the demo is due."))
    assert prompt.startswith("=== SFL GATE OUTPUT")
    assert "RAW INPUT:" in prompt
    assert "REGISTER (context of situation):" in prompt
    assert "Field (subject matter):" in prompt
    assert "Tenor (stance and relation):" in prompt
    assert "CLAUSE-BY-CLAUSE METAFUNCTIONAL ANNOTATION:" in prompt
    assert "Ideational: process=material" in prompt
    assert "Interpersonal: mood=declarative" in prompt
    assert "Textual: theme=" in prompt
    assert "TASK DIRECTIVES:" in prompt
    assert "SFL reading" in prompt


def test_prompt_is_deterministic():
    raw = "Maybe you could explain the migration plan, but keep it short."
    assert build_prompt(analyze(raw)) == build_prompt(analyze(raw))


def test_directives_reflect_annotation():
    raw = "You must review the security report carefully."
    prompt = build_prompt(analyze(raw))
    assert "Ideational" in prompt
    assert "match the input's stance" in prompt
    assert "open from the theme" in prompt
