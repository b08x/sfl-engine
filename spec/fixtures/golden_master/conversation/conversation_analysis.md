# Conversation Analysis: sample

**Generated**: 2026-07-24T00:25:49-04:00
**Turns**: 5 | **Speakers**: Alice, Bob


---

## ⚠️ Data Quality

**8 of 8 clauses (100.0%)** carry fallback/stub interpersonal values (tenor=0.5, modality=0.5, mood=declarative) instead of LLM annotations. Tenor and modality averages are biased toward 0.5.

**Pass 2 did not run for any clause — the interpersonal values in this report are placeholders, not findings.**

---

## Summary

This analysis tracks **tenor evolution** (formality shifts), **field evolution** (topic/process changes), and **tenor ↔ field correlations** across the conversation.

---

## Speaker Profiles

| Speaker | Avg Tenor | Range | Variance | Avg Modality |
|---------|-----------|-------|----------|--------------|
| Alice   | 0.5 (mixed) | [0.5, 0.5] | 0.0 | 0.5 |
| Bob     | 0.5 (mixed) | [0.5, 0.5] | 0.0 | 0.5 |

---

## Cohesion Metrics

| Turn | Speaker | Repetition | Conjunctions | Pronouns |
|:-----|:---------|:-----------|:-------------|:---------|
| 1 | Alice | 0.0 | 0.0 | 0.071 |
| 2 | Bob | 0.0 | 0.0 | 0.133 |
| 3 | Alice | 0.0 | 0.0 | 0.083 |
| 4 | Bob | 0.0 | 0.0 | 0.235 |
| 5 | Alice | 0.0 | 0.0 | 0.125 |

---

## Tenor ↔ Field Correlations

| Process Type | Avg Tenor | Avg Modality | Count |
|--------------|-----------|--------------|-------|
| material | 0.5 | 0.5 | 3 |
| relational | 0.5 | 0.5 | 3 |
| mental | 0.5 | 0.5 | 2 |

---

## Generated Insights

1. Alice contributed 3 of 5 turns

2. 3 topics identified across the conversation

### 🏷️ Topic Modeling

**3 topics identified**

- **Topic 0**: 
- **Topic 1**: 
- **Topic 2**: 


### 📖 Example Passages

#### Most Formal (score: 0.5)
> "Hey, I'm running into a weird issue with the auth flow."

*— Alice. Highest tenor (formality) score in the conversation.*

#### Most Casual (score: 0.5)
> "Hey, I'm running into a weird issue with the auth flow."

*— Alice. Lowest tenor score; uses informal register.*

#### Most Certain (score: 0.5)
> "Hey, I'm running into a weird issue with the auth flow."

*— Alice. Highest modality weight; assertive and definitive language.*

#### Most Hedged (score: 0.5)
> "Hey, I'm running into a weird issue with the auth flow."

*— Alice. Lowest modality weight; frequent use of hedging or uncertainty.*


---

## Methodology

**SFL Framework**: Two-Pass SFL Compiler (sfl-compiler)
- **Pass 1**: Syntactic parsing (spaCy) + Ideational extraction (process types, participants)
- **Pass 2**: Interpersonal annotation (DSPy.rb + LLM) → mood, modality, tenor, attitude

**Tenor Scale**: 0.0 (informal/casual) ↔ 1.0 (formal/technical)
**Modality Scale**: 0.0 (hedged/uncertain) ↔ 1.0 (certain/assertive)

