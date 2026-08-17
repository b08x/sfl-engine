# Classification corpus schema

`classification_corpus.json` is a ground-truth reference dataset. It is not an alias table and must not be used to add normalization mappings.

## Top-level object

- `$schema`: JSON Schema draft URL.
- `schema_version`: dataset schema version string.
- `description`: purpose and no-alias constraint.
- `entries`: array of labeled examples; at least one `compound` and one `fragment` entry is required.

## Entry fields

| Field | Type | Required | Meaning |
|---|---|---:|---|
| `id` | string | yes | Stable unique example identifier (`compound-NNN` or `fragment-NNN`). |
| `raw_classification` | string | yes | Exact classification text presented to a parser, including whitespace and punctuation edge cases. |
| `canonical_label` | enum | yes | Dataset ground-truth category: `compound` or `fragment`. This is not a parser output alias. |
| `expected_parsed_output` | object or null | yes | Expected parser result when one can be stated. Compound results use `{dimension, values}`; single fragment results use `{dimension, value}`. `null` means incomplete input should remain unresolved. |
| `confidence` | enum | yes | Evidence quality for the expected result: `high`, `medium`, or `low`. Low confidence examples are intentionally retained as review cases. |

## Classification definitions

- **compound**: a raw string contains multiple classification tokens or components, regardless of separator (`+`, comma, `and`, `>`, or another observed delimiter).
- **fragment**: a partial, incomplete, elliptical, missing, or fragmentary classification string. A fragment may still have a useful expected value, but unresolved fragments use `null`.

## Loading and validation

The file is ordinary JSON and can be loaded with Ruby's stdlib:

```ruby
require "json"
corpus = JSON.parse(File.read("data/reference/classification_corpus.json"))
entries = corpus.fetch("entries")
```

A validation consumer should check required keys, unique IDs, the two allowed labels, and the confidence enum before comparing pipeline output. The dataset intentionally does not require the production registry to normalize every raw string: it is a validation reference, not an alias source.

Current contents: 60 entries, evenly split between compound and fragment examples. No aliases or production mappings are declared.

## Provenance and limitations

Examples are hand-curated from the production classification vocabulary and observed separator/incompleteness patterns in `SFL::Core::ClassificationRegistry`. They are test fixtures for parser behavior, not a linguistically exhaustive gold standard. Low-confidence entries require review before being promoted to implementation behavior.

The corpus is deliberately independent of `ClassificationRegistry` so that future alias or mapping changes cannot silently rewrite the ground truth.

## JSON Schema shape

The JSON file uses these constraints conceptually: `entries` is required and non-empty; each entry requires `id`, `raw_classification`, `canonical_label`, `expected_parsed_output`, and `confidence`; `canonical_label` is restricted to `compound|fragment`; `confidence` is restricted to `high|medium|low`; IDs are unique. The file's `$schema` identifies the standard used for a future machine-readable validator.

No aliases are introduced by this task.

