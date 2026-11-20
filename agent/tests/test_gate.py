from sfl_gate.gate import analyze


def test_same_input_gives_same_analysis():
    a = analyze("We must deploy the service before Friday.")
    b = analyze("We must deploy the service before Friday.")
    assert a == b


def test_material_process_with_participants_and_circumstance():
    result = analyze("The team deploys the service before Friday.")
    clause = result.clauses[0]
    assert clause.process_type == "material"
    assert clause.process_verb == "deploy"
    roles = {p.role for p in clause.participants}
    assert roles == {"Actor", "Goal"}
    assert any(c.type == "time" for c in clause.circumstances)


def test_mental_process():
    clause = analyze("I think the design works.").clauses[0]
    assert clause.process_type == "mental"
    assert clause.process_verb == "think"
    assert clause.participants[0].role == "Senser"


def test_relational_process():
    clause = analyze("The API is slow.").clauses[0]
    assert clause.process_type == "relational"
    assert clause.participants[0].role == "Carrier"


def test_verbal_process():
    clause = analyze("Tell me about the deployment.").clauses[0]
    assert clause.process_type == "verbal"
    assert clause.mood == "imperative"
    roles = {p.role for p in clause.participants}
    assert roles == {"Receiver", "Verbiage"}


def test_existential_process():
    clause = analyze("There is a problem with the build.").clauses[0]
    assert clause.process_type == "existential"


def test_mood_detection():
    assert analyze("What is the build status?").clauses[0].mood == "interrogative"
    assert analyze("Close the door.").clauses[0].mood == "imperative"
    assert analyze("The build is green.").clauses[0].mood == "declarative"


def test_modality_and_appraisal():
    clause = analyze("You must fix the extremely slow query.").clauses[0]
    assert ("must", "obligation", "high") in clause.modality
    assert "extremely" in clause.appraisal


def test_theme_rheme():
    clause = analyze("On Friday the team ships the release.").clauses[0]
    assert clause.theme == "On Friday"
    assert clause.rheme.startswith("the team")


def test_clause_segmentation_and_cohesion():
    result = analyze("The build failed, so we reverted the commit because the tests broke.")
    assert len(result.clauses) >= 3
    assert "causal" in result.cohesion


def test_register_variables():
    result = analyze("Can you quickly summarize the quarterly revenue report?")
    assert result.field
    assert "help-seeking" in result.tenor
    assert 0.0 < result.lexical_density <= 1.0


def test_empty_and_marginal_input():
    result = analyze("")
    assert result.clauses == []
    result = analyze("   ")
    assert result.clauses == []
    result = analyze("42")
    assert len(result.clauses) == 1
    assert result.clauses[0].process_type == "unclassified"
