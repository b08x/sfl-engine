"""Deterministic Systemic Functional Linguistics (SFL) gate.

Pure Python, no model calls: the same input always produces the same
analysis. The gate segments raw natural-language input into clauses and
annotates each clause with the three SFL metafunctions:

- Ideational (experiential): transitivity -- process type, participants,
  circumstances.
- Interpersonal: mood, modality, appraisal.
- Textual: theme/rheme, cohesive devices, lexical density.

It also derives the register variables field, tenor and mode, which
``sfl_gate.prompt`` turns into the prompt handed to the functional agent.

The lexicons and rules below are deliberately small and fixed. They are
heuristics, not a parser: the gate trades linguistic precision for
determinism, which is the point of the demonstration.
"""

import re
from collections import Counter
from dataclasses import dataclass
from dataclasses import field as dc_field


@dataclass
class Participant:
    role: str
    text: str


@dataclass
class Circumstance:
    type: str
    text: str


@dataclass
class ClauseAnalysis:
    text: str
    process_type: str = "unclassified"
    process_verb: str = ""
    participants: list[Participant] = dc_field(default_factory=list)
    circumstances: list[Circumstance] = dc_field(default_factory=list)
    mood: str = "declarative"
    modality: list[tuple[str, str, str]] = dc_field(default_factory=list)
    appraisal: list[str] = dc_field(default_factory=list)
    theme: str = ""
    rheme: str = ""


@dataclass
class Analysis:
    raw: str
    clauses: list[ClauseAnalysis] = dc_field(default_factory=list)
    field: list[str] = dc_field(default_factory=list)
    tenor: str = ""
    mode: str = "written input, monologic"
    cohesion: list[str] = dc_field(default_factory=list)
    lexical_density: float = 0.0


MATERIAL_VERBS = {
    "run", "make", "build", "write", "create", "send", "deploy", "generate",
    "produce", "transform", "analyze", "analyse", "process", "compute",
    "fetch", "deliver", "move", "change", "do", "implement", "provide",
    "use", "apply", "open", "close", "start", "stop", "finish", "add",
    "remove", "delete", "update", "fix", "test", "show", "give", "take",
    "get", "put", "set", "keep", "find", "help", "work", "check", "review",
    "summarize", "summarise", "explain", "break", "split", "merge", "copy",
    "return", "call", "connect", "install", "configure", "launch", "run",
    "ship", "summarise", "categorize", "categorise", "convert", "translate",
}

MENTAL_VERBS = {
    "think", "know", "believe", "feel", "want", "need", "like", "understand",
    "see", "hear", "wonder", "consider", "expect", "prefer", "love", "hate",
    "remember", "forget", "guess", "assume", "hope", "wish", "realize",
    "realise", "notice", "learn", "decide", "doubt", "imagine", "suppose",
}

RELATIONAL_VERBS = {
    "is", "are", "was", "were", "am", "be", "being", "been", "has", "have",
    "had", "consists", "consist", "comprises", "comprise", "represents",
    "represent", "means", "mean", "equals", "equal", "remains", "remain",
    "seems", "seem", "appears", "appear", "becomes", "become", "involves",
    "involve", "entails", "entail", "constitutes", "constitute", "serves",
    "serve", "contains", "contain", "includes", "include", "depends", "depend",
    "belongs", "belong", "costs", "cost", "matters", "matter",
}

VERBAL_VERBS = {
    "say", "tell", "ask", "state", "mention", "report", "argue", "suggest",
    "request", "announce", "answer", "discuss", "describe", "claim", "promise",
    "reply", "respond", "complain", "insist", "warn", "name", "call",
}

BEHAVIORAL_VERBS = {
    "smile", "laugh", "cry", "watch", "look", "listen", "sigh", "breathe",
    "sleep", "wake", "sit", "stand", "walk", "wait", "hesitate", "stare",
    "glance", "nod", "frown",
}

VERB_LEXICONS = (
    ("material", MATERIAL_VERBS),
    ("mental", MENTAL_VERBS),
    ("relational", RELATIONAL_VERBS),
    ("verbal", VERBAL_VERBS),
    ("behavioral", BEHAVIORAL_VERBS),
)

ALL_VERBS = MATERIAL_VERBS | MENTAL_VERBS | RELATIONAL_VERBS | VERBAL_VERBS | BEHAVIORAL_VERBS

MODALITY = {
    "must": ("obligation", "high"),
    "should": ("obligation", "median"),
    "ought": ("obligation", "median"),
    "shall": ("instruction", "high"),
    "will": ("prediction", "median"),
    "would": ("prediction", "low"),
    "can": ("ability", "median"),
    "could": ("ability", "low"),
    "may": ("possibility", "median"),
    "might": ("possibility", "low"),
}

INTENSIFIERS = {
    "very", "really", "extremely", "absolutely", "totally", "quite",
    "super", "highly", "deeply", "strongly", "completely", "incredibly",
    "terribly", "awfully", "hugely", "insanely", "particularly",
}

WH_WORDS = {"what", "who", "whom", "whose", "when", "where", "why", "how", "which"}

AUXILIARIES = {"do", "does", "did", "done", "doing", "is", "are", "was", "were", "am", "be", "been", "being", "have", "has", "had", "having"} | set(MODALITY)

CLAUSE_MARKERS = {
    "and", "but", "or", "nor", "so", "yet",
    "because", "although", "though", "while", "whereas", "if", "unless",
    "when", "wherever",
}

COHESION = {
    "additive": {"and", "also", "moreover", "furthermore", "additionally", "besides", "plus"},
    "adversative": {"but", "however", "yet", "although", "though", "whereas", "nevertheless", "nonetheless", "instead"},
    "causal": {"because", "so", "therefore", "thus", "consequently", "hence", "accordingly", "since", "otherwise"},
    "temporal": {"then", "next", "finally", "meanwhile", "later", "afterwards", "subsequently", "first", "second", "lastly"},
}

LOCATION_PREPS = {"in", "on", "at", "under", "over", "near", "inside", "outside", "around", "above", "below", "behind", "beside", "between", "across", "through", "against", "into", "onto", "upon", "toward", "towards", "within"}
TIME_PREPS = {"during", "after", "before", "until", "till", "since", "by"}
ACCOMPANIMENT_PREPS = {"with", "without"}
CAUSE_PREPS = {"from", "due", "owing"}

DISCOURSE_MARKERS = {
    "hey", "hi", "hello", "ok", "okay", "well", "um", "uh", "like",
    "basically", "actually", "anyway", "maybe", "sort", "kind", "hmm",
}

TIME_ADVERBS = {"today", "tomorrow", "yesterday", "now", "then", "later", "soon", "recently", "currently", "immediately", "eventually", "finally", "already", "still", "yet", "always", "never", "often", "sometimes", "usually", "regularly"}

TIME_NOUNS = {
    "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
    "sunday", "january", "february", "march", "april", "may", "june",
    "july", "august", "september", "october", "november", "december",
    "week", "weeks", "month", "months", "year", "years", "day", "days",
    "hour", "hours", "minute", "minutes", "morning", "afternoon",
    "evening", "night", "weekend", "quarter", "today", "tomorrow",
    "yesterday", "deadline", "noon", "midnight",
}

STOPWORDS = {
    "a", "an", "the", "of", "to", "in", "on", "at", "for", "and", "but", "or",
    "nor", "so", "yet", "is", "are", "was", "were", "am", "be", "been",
    "being", "it", "its", "this", "that", "these", "those", "i", "you", "he",
    "she", "we", "they", "me", "him", "her", "us", "them", "my", "your",
    "his", "our", "their", "there", "here", "as", "if", "then", "than",
    "with", "without", "from", "by", "about", "into", "onto", "up", "down",
    "out", "off", "over", "under", "again", "not", "no", "yes", "do", "does",
    "did", "done", "doing", "have", "has", "had", "having", "will", "would",
    "can", "could", "may", "might", "must", "should", "shall", "ought",
    "please", "just", "also", "very", "really", "some", "any", "all",
    "each", "every", "both", "few", "more", "most", "other", "such", "own",
    "same", "too", "s", "t", "ll", "ve", "re", "d", "m",
}

TOKEN_RE = re.compile(r"[A-Za-z]+(?:'[A-Za-z]+)?|[0-9]+|[^\sA-Za-z0-9]")
SENTENCE_SPLIT_RE = re.compile(r"([.!?]+)")
CLAUSE_MARKER_RE = re.compile(r"\b(" + "|".join(sorted(CLAUSE_MARKERS)) + r")\b")


def _tokens(text: str) -> list[str]:
    return [t for t in TOKEN_RE.findall(text) if t.strip()]


def _words(text: str) -> list[str]:
    return [t.lower() for t in TOKEN_RE.findall(text) if t[0].isalpha()]


def _verb_lemmas(word: str) -> set[str]:
    """Deterministic candidate lemmas for a word form."""
    w = word.lower().strip(".,;:!?")
    out = {w}
    if w.endswith("ies"):
        out.add(w[:-3] + "y")
    if w.endswith("es"):
        out.add(w[:-2])
    if w.endswith("s"):
        out.add(w[:-1])
    if w.endswith("ing"):
        out.add(w[:-3])
        out.add(w[:-3] + "e")
    if w.endswith("ed"):
        out.add(w[:-2])
        out.add(w[:-1])
    if w.endswith("d"):
        out.add(w[:-1])
    return out


def _find_main_verb(words: list[str]) -> tuple[int, str, str] | None:
    """Return (index, lemma, process_type) of the clause's main verb.

    Lexical verbs win over auxiliary uses of "be"/"have", so "is running"
    is material while "is slow" falls through to the relational pass.
    """
    for i, w in enumerate(words):
        if w in MODALITY or w in AUXILIARIES:
            continue
        for lemma in _verb_lemmas(w):
            for ptype, lexicon in VERB_LEXICONS:
                if ptype == "relational":
                    continue
                if lemma in lexicon:
                    return i, lemma, ptype
    for i, w in enumerate(words):
        for lemma in _verb_lemmas(w):
            if lemma in RELATIONAL_VERBS:
                return i, lemma, "relational"
    return None


def _span_text(tokens: list[str]) -> str:
    return " ".join(tokens).strip()


GOAL_TERMINATORS = LOCATION_PREPS | TIME_PREPS | ACCOMPANIMENT_PREPS | CAUSE_PREPS | {"about", "of", "for", "onto", "via"}

PERSONAL_PRONOUNS = {"me", "us", "him", "her", "them", "you"}


def _participants(clause_tokens: list[str], verb_idx: int, process: str) -> list[Participant]:
    roles = {
        "material": ("Actor", "Goal"),
        "mental": ("Senser", "Phenomenon"),
        "relational": ("Carrier", "Attribute"),
        "verbal": ("Sayer", "Verbiage"),
        "behavioral": ("Behaver", "Behaviour"),
        "existential": (None, "Existent"),
    }
    subject_role, object_role = roles[process]
    participants: list[Participant] = []

    pre = [t for t in clause_tokens[:verb_idx] if t.isalpha()]
    subject_tokens = []
    for t in pre:
        lw = t.lower()
        if lw in MODALITY or lw in AUXILIARIES or lw in CLAUSE_MARKERS:
            if subject_tokens:
                break
            continue
        if lw.endswith("ly") and len(lw) > 4 and lw not in STOPWORDS:
            continue
        if lw in INTENSIFIERS:
            continue
        subject_tokens.append(t)
    if subject_tokens and subject_role is not None:
        participants.append(Participant(role=subject_role, text=_span_text(subject_tokens)))

    if object_role is not None:
        post = clause_tokens[verb_idx + 1:]
        goal_tokens = []
        for t in post:
            if not t.isalpha():
                if not goal_tokens:
                    continue
                break
            if t.lower() in GOAL_TERMINATORS or t.lower() in CLAUSE_MARKERS or t.lower() in MODALITY:
                break
            goal_tokens.append(t)
        if process == "verbal":
            verbiage_tokens = []
            receiver = None
            for t in post:
                if not t.isalpha():
                    if not verbiage_tokens and receiver is None:
                        continue
                    break
                lw = t.lower()
                if lw in MODALITY or lw in CLAUSE_MARKERS:
                    break
                if receiver is None and lw in PERSONAL_PRONOUNS:
                    receiver = t
                    continue
                if lw == "about":
                    continue
                if lw in GOAL_TERMINATORS:
                    break
                verbiage_tokens.append(t)
            if receiver is not None:
                participants.append(Participant(role="Receiver", text=receiver))
            if verbiage_tokens:
                participants.append(Participant(role="Verbiage", text=_span_text(verbiage_tokens)))
            return participants
        if goal_tokens:
            participants.append(Participant(role=object_role, text=_span_text(goal_tokens)))
    return participants

def _circumstances(clause_tokens: list[str]) -> list[Circumstance]:
    found: list[Circumstance] = []
    lowered = [t.lower() for t in clause_tokens]
    i = 0
    while i < len(clause_tokens):
        w = lowered[i]
        if w in ("in", "on", "at") and i + 1 < len(lowered) and lowered[i + 1] in TIME_NOUNS:
            found.append(Circumstance("time", _span_text(clause_tokens[i:i + 3])))
            i += 3
        elif w in LOCATION_PREPS:
            found.append(Circumstance("location", _span_text(clause_tokens[i:i + 4])))
            i += 4
        elif w in TIME_PREPS or w in TIME_NOUNS:
            found.append(Circumstance("time", _span_text(clause_tokens[i:i + 4])))
            i += 4
        elif w in ACCOMPANIMENT_PREPS:
            found.append(Circumstance("accompaniment", _span_text(clause_tokens[i:i + 4])))
            i += 4
        elif w == "due" and i + 2 < len(lowered) and lowered[i + 1] == "to":
            found.append(Circumstance("cause", _span_text(clause_tokens[i:i + 5])))
            i += 5
        elif w in TIME_ADVERBS:
            found.append(Circumstance("time", clause_tokens[i]))
            i += 1
        elif w == "about":
            found.append(Circumstance("matter", _span_text(clause_tokens[i:i + 4])))
            i += 4
        elif w.endswith("ly") and len(w) > 4 and w not in STOPWORDS and w not in TIME_NOUNS:
            found.append(Circumstance("manner", clause_tokens[i]))
            i += 1
        else:
            i += 1
    return found


def _mood(clause_tokens: list[str], sentence: str, is_final: bool) -> str:
    words = [t for t in clause_tokens if t.isalpha()]
    if is_final and sentence.rstrip().endswith("?"):
        return "interrogative"
    if words and words[0].lower() in WH_WORDS:
        return "interrogative"
    if words and words[0].lower() in AUXILIARIES and len(words) > 1:
        return "interrogative"
    verb = _find_main_verb([w.lower() for w in words])
    if verb and verb[0] == 0:
        return "imperative"
    return "declarative"


ARTICLES = {"the", "a", "an", "this", "that", "these", "those"}


def _theme_rheme(clause_tokens: list[str]) -> tuple[str, str]:
    words = [t for t in clause_tokens if t.strip()]
    if not words:
        return "", ""
    if words[0].lower() in LOCATION_PREPS or words[0].lower() in TIME_PREPS or words[0].lower() in ACCOMPANIMENT_PREPS:
        theme_tokens = [words[0]]
        for t in words[1:4]:
            if t.lower() in ARTICLES:
                break
            theme_tokens.append(t)
        theme = _span_text(theme_tokens)
        return theme, _span_text(words[len(theme_tokens):])
    theme = words[0]
    return theme, _span_text(words[1:])


def _analyze_clause(clause: str, sentence: str, is_final: bool) -> ClauseAnalysis:
    tokens = _tokens(clause)
    words = [t for t in tokens if t.isalpha()]
    lowered = [w.lower() for w in words]

    analysis = ClauseAnalysis(text=clause.strip())

    if len(lowered) > 1 and lowered[0] == "there" and lowered[1] in ("be", "is", "are", "was", "were", "am"):
        verb = (1, "be" if lowered[1] == "be" else lowered[1], "existential")
    else:
        verb = _find_main_verb(lowered)
    if verb:
        verb_idx_in_words, lemma, ptype = verb
        if (
            len(lowered) > 1
            and lowered[0] == "there"
            and verb_idx_in_words == 1
            and lemma in ("be", "is", "are", "was", "were", "am")
        ):
            ptype = "existential"
        analysis.process_type = ptype
        analysis.process_verb = lemma
        clause_start = 0
        while clause_start < len(tokens) and not tokens[clause_start].isalpha():
            clause_start += 1
        word_positions = [i for i, t in enumerate(tokens) if t.isalpha()]
        verb_clause_idx = word_positions[verb_idx_in_words] if verb_idx_in_words < len(word_positions) else 0
        analysis.participants = _participants(tokens, verb_clause_idx, ptype)
    else:
        analysis.process_type = "unclassified"
        analysis.process_verb = ""

    analysis.circumstances = _circumstances(tokens)
    analysis.mood = _mood(tokens, sentence, is_final)

    for i, w in enumerate(lowered):
        if w in MODALITY:
            kind, degree = MODALITY[w]
            analysis.modality.append((words[i], kind, degree))
        if w in INTENSIFIERS:
            analysis.appraisal.append(words[i])

    theme, rheme = _theme_rheme(tokens)
    analysis.theme = theme
    analysis.rheme = rheme
    return analysis


def _segment(raw: str) -> list[tuple[str, str, bool]]:
    """Return (clause, containing sentence, clause is sentence-final) triples."""
    pairs: list[tuple[str, str, bool]] = []
    chunks = [c for c in SENTENCE_SPLIT_RE.split(raw) if c.strip()]
    sentences: list[str] = []
    buffer = ""
    for chunk in chunks:
        buffer += chunk
        if SENTENCE_SPLIT_RE.fullmatch(chunk):
            sentences.append(buffer)
            buffer = ""
    if buffer.strip():
        sentences.append(buffer)
    for sentence in sentences:
        terminated = sentence.strip()
        if not terminated:
            continue
        bounds = [m.start() for m in CLAUSE_MARKER_RE.finditer(terminated)]
        if not bounds:
            pairs.append((terminated, terminated, True))
            continue
        segments: list[str] = [terminated[: bounds[0]]]
        for j, start in enumerate(bounds):
            end = bounds[j + 1] if j + 1 < len(bounds) else len(terminated)
            segments.append(terminated[start:end])
        for k, seg in enumerate(segments):
            seg = seg.strip(" ,;:")
            if seg:
                pairs.append((seg, terminated, k == len(segments) - 1))
    return pairs


def _cohesion(raw_words: list[str]) -> list[str]:
    devices: list[str] = []
    for kind, items in COHESION.items():
        if any(w in items for w in raw_words):
            devices.append(kind)
    return devices


def _lexical_density(raw_words: list[str]) -> float:
    if not raw_words:
        return 0.0
    content = [w for w in raw_words if w not in STOPWORDS]
    return round(len(content) / len(raw_words), 2)


def _field_words(raw_words: list[str]) -> list[str]:
    skip = STOPWORDS | INTENSIFIERS | DISCOURSE_MARKERS | WH_WORDS | set(MODALITY)
    content = [w for w in raw_words if w not in skip and len(w) > 2]
    counts = Counter(content)
    ranked = sorted(counts, key=lambda w: (-counts[w], content.index(w)))
    return ranked[:5]


def _tenor(clauses: list[ClauseAnalysis]) -> str:
    moods = [c.mood for c in clauses]
    if "interrogative" in moods:
        stance = "help-seeking (question posed to the agent)"
    elif "imperative" in moods:
        stance = "directive (speaker expects action)"
    else:
        stance = "informative (speaker states or reports)"
    modal_kinds = {kind for c in clauses for _, kind, _ in c.modality}
    if "obligation" in modal_kinds:
        stance += "; strong expectation of compliance"
    elif modal_kinds:
        stance += "; hedged or tentative expectation"
    return stance


def analyze(raw: str) -> Analysis:
    """Run the full deterministic SFL analysis over raw input text."""
    raw = raw.strip()
    raw_words = _words(raw)
    clauses = [_analyze_clause(clause, sentence, is_final) for clause, sentence, is_final in _segment(raw)]
    return Analysis(
        raw=raw,
        clauses=clauses,
        field=_field_words(raw_words),
        tenor=_tenor(clauses),
        mode="written input, monologic",
        cohesion=_cohesion(raw_words),
        lexical_density=_lexical_density(raw_words),
    )
