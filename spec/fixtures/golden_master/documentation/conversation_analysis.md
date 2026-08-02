# Conversation Analysis: sample

**Generated**: 2026-07-24T00:26:33-04:00
**Sections**: 3 | **Headings**: Introduction, Usage, Advanced Topics

> ## 🚨 LOW CONFIDENCE: 6 clauses (minimum 30 recommended)
> Aggregate modality/tenor scores below this sample size are statistically unreliable. Treat every finding in this report as provisional.

---

## Summary

This analysis tracks **tenor evolution** (formality shifts), **field evolution** (topic/process changes), and **tenor ↔ field correlations** across the conversation.

---

## Section Profiles

| Section | Avg Tenor | Range | Variance | Avg Modality |
|---------|-----------|-------|----------|--------------|
| Introduction | 0.5 (mixed) | [0.5, 0.5] | 0.0 | 1.0 |
| Usage   | 0.5 (mixed) | [0.5, 0.5] | 0.0 | 0.9 |
| Advanced Topics | 0.5 (mixed) | [0.5, 0.5] | 0.0 | 0.9 |

---

## Cohesion Metrics

| Section | Speaker | Repetition | Conjunctions | Pronouns |
|:-----|:---------|:-----------|:-------------|:---------|
| 1 | Introduction | 0.0 | 0.045 | 0.045 |
| 2 | Usage | 0.0 | 0.0 | 0.0 |
| 3 | Advanced Topics | 0.077 | 0.1 | 0.0 |

---

## Tenor ↔ Field Correlations

| Process Type | Avg Tenor | Avg Modality | Count |
|--------------|-----------|--------------|-------|
| material | 0.5 | 0.933 | 6 |

---

## Generated Insights

1. 3 topics identified across the document

### 🏷️ Topic Modeling

**3 topics identified**

- **Topic 0**: 
- **Topic 1**: 
- **Topic 2**: 


### 📖 Example Passages

#### Most Formal Section (score: 0.5)
> "This document introduces the main concepts of the system.  It provides an overview of the architecture and the key components...."

*— Introduction. Highest formality score in the document.*

#### Most Assertive Section (score: 1.0)
> "This document introduces the main concepts of the system.  It provides an overview of the architecture and the key components...."

*— Introduction. Highest certainty score; authoritative stance.*


### 🔍 Reasoning Traces

> "This document introduces the main concepts of the system."

<details>
<summary>Reasoning: unknown (confidence 0.5)</summary>

| Premise | Type | Value | Weight |
|---|---|---|---|
| mood | linguistic | declarative | 1.0 |
| modality | linguistic | 1.0 | 1.0 |
| tenor | linguistic | 0.5 | 1.0 |
| theme | linguistic | This document | 1.0 |
| rheme | linguistic | introduces the main concepts of the system | 1.0 |

Derivation: `03d16326137e100de8fa78da3f0c545b6792860117b16a73d93e868438f7705b`
</details>

> "It provides an overview of the architecture and the key components."

<details>
<summary>Reasoning: unknown (confidence 0.5)</summary>

| Premise | Type | Value | Weight |
|---|---|---|---|
| mood | linguistic | declarative | 1.0 |
| modality | linguistic | 1.0 | 1.0 |
| tenor | linguistic | 0.5 | 1.0 |
| theme | linguistic | It | 1.0 |
| rheme | linguistic | provides an overview of the architecture and the key components | 1.0 |

Derivation: `a0ffaf863d15440b9646892af256567c013f6f9d10db7866b7ddf2f7fabe5228`
</details>

> "Users can invoke the command-line interface to analyze text."

<details>
<summary>Reasoning: default (confidence 0.5)</summary>

| Premise | Type | Value | Weight |
|---|---|---|---|
| mood | linguistic | declarative | 1.0 |
| modality | linguistic | can | 0.8 |
| tenor | linguistic | neutral | 0.5 |
| theme | linguistic | Users | 1.0 |

Derivation: `1d230008c8f187b1654cff6760e780b6e4d2f49df0536a514aafb640b69369d8`
</details>

> "The tool produces structured linguistic annotations for each sentence."

<details>
<summary>Reasoning: default (confidence 0.5)</summary>

| Premise | Type | Value | Weight |
|---|---|---|---|
| mood | linguistic | declarative | 1.0 |
| modality | linguistic | none | 1.0 |
| tenor | linguistic | neutral | 0.5 |
| theme | linguistic | The tool | 1.0 |

Derivation: `27a20ebee10f1acb3b441364a123e3329c01c71ee9feee8cadfbaf2762dcc271`
</details>

> "The pipeline supports custom models and batch processing."

<details>
<summary>Reasoning: unknown (confidence 0.5)</summary>

| Premise | Type | Value | Weight |
|---|---|---|---|
| clause | fact | The pipeline supports custom models and batch processing | 1.0 |

Derivation: `f06199e4d0595c127b5c5f112f0aa2e101893c32e008adbb499c64cda6e12abc`
</details>

> "Operators may configure concurrency and batch size via environment variables."

<details>
<summary>Reasoning: unknown (confidence 0.5)</summary>

| Premise | Type | Value | Weight |
|---|---|---|---|
| clause | fact | Operators may configure concurrency and batch size via environment variables | 0.8 |

Derivation: `7d20698c21a4d622fc74cd171a63750c0b3935ad5be891850f13ed26960c70e1`
</details>

---

## Methodology

**SFL Framework**: Two-Pass SFL Engine (sfl-engine)
- **Pass 1**: Syntactic parsing (spaCy) + Ideational extraction (process types, participants)
- **Pass 2**: Interpersonal annotation (DSPy.rb + LLM) → mood, modality, tenor, attitude

**Tenor Scale**: 0.0 (informal/casual) ↔ 1.0 (formal/technical)
**Modality Scale**: 0.0 (hedged/uncertain) ↔ 1.0 (certain/assertive)

