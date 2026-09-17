# API Reference

This document covers all HTTP routes exposed by the `sfl-engine` API. For the underlying database schema, see [Data Model](data-model.md). For system-level diagrams of how these routes fit into the architecture, see [Architecture Diagrams](architecture-diagrams.md).

> **Note:** All `curl` examples assume `localhost:3001` (the default for local development). Adjust host and port for your environment — the engine supports `HOST` and `PORT` env vars.

## Wire Format

The API uses `SFL::Core::Wire.dump` to serialize types across the process boundary. Times are converted to ISO8601 strings. 

### `AnnotatedClause`

```json
{
  "id": "clause-uuid",
  "text": "The engine compiles the text.",
  "syntactic": {
    "id": "syntactic-uuid",
    "text": "The engine compiles the text.",
    "tokens": [...],
    "groups": [...],
    "root_index": 2,
    "sentence_index": 0,
    "document_id": "doc-uuid",
    "parent_clause_id": null,
    "readability": null
  },
  "ideational": {
    "clause_id": "clause-uuid",
    "process_type": "material",
    "participants": [...],
    "circumstances": [...],
    "raw_transitivity": {...}
  },
  "interpersonal": {
    "clause_id": "clause-uuid",
    "mood": "declarative",
    "modality_weight": 0.8,
    "tenor": 0.5,
    "speaker_attitude": "objective",
    "reasoning": "...",
    "annotation_source": "llm",
    "reasoning_trace": {
      "premises": [{ "label": "...", "value": "..." }],
      "inference_rule": "SFL mood + modality rule",
      "conclusion": { "mood": "declarative", "modality_weight": 0.8 },
      "confidence": 0.92,
      "derivation_hash": "sha256-hex-string",
      "generated_at": "2023-01-01T00:00:00Z"
    },
    "raw_classification": "declarative",
    "classification_status": "canonical",
    "untrusted": false
  },
  "textual": null,
  "document_id": "doc-uuid",
  "compiled_at": "2023-01-01T00:00:00Z",
  "untrusted": false
}
```

### `RetrievalResult`

```json
{
  "clause_id": "clause-uuid",
  "text": "The engine compiles the text.",
  "document_id": "doc-uuid",
  "rrf_score": 0.95,
  "semantic_rank": 1,
  "keyword_rank": 2,
  "mood": "indicative",
  "tenor": 0.5,
  "process_type": "material",
  "modality_weight": 0.8,
  "annotation_source": "llm",
  "untrusted": false,
  "parent_clause_id": null
}
```

## Routes

### Health

#### `GET /health`

**Purpose:** Health check endpoint to verify API availability.

**Request:** None

**Response (200):**
```json
{
  "status": "ok"
}
```

**Example:**
```bash
curl -X GET http://localhost:3001/health
```

---

### Compilation

#### `POST /pipeline/compile`

**Purpose:** Compiles raw text into annotated clauses using the two-pass pipeline.

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `text` | string | Yes | - | The raw text to compile |
| `document_id` | string | No | `api-<uuid>` | Document identifier |
| `store` | boolean | No | `false` | Whether to persist clauses to Postgres |
| `embed` | boolean | No | `false` | Whether to generate vector embeddings |

**Response (200):** Array of `AnnotatedClause` (Wire format)

**Errors:**
| Status | Condition |
|--------|-----------|
| 400 | `text` is missing or empty |

**Example:**
```bash
curl -X POST http://localhost:3001/pipeline/compile \
  -H "Content-Type: application/json" \
  -d '{"text": "Compile this text.", "store": true}'
```

---

### Retrieval

#### `POST /retrieve`

**Purpose:** Retrieves clauses using Hybrid RRF (vector + keyword) and scalar filters.

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `query` | string | Yes | - | The search query |
| `limit` | integer | No | `10` | Maximum results to return |
| `filters` | object | No | `{}` | `RetrievalFilters` (see below) |

**RetrievalFilters fields:**
- `mood` (enum: declarative, interrogative, imperative, exclamative, indicative, minor, fragment)
- `process_type` (enum: material, mental, relational, behavioral, verbal, existential)
- `source_type` (string)
- `min_modality` (float 0.0 - 1.0)
- `max_modality` (float 0.0 - 1.0)
- `min_tenor` (float 0.0 - 1.0)
- `max_tenor` (float 0.0 - 1.0)

**Response (200):**
```json
{
  "query": "search term",
  "results": [ /* Array of RetrievalResult (Wire format) */ ],
  "count": 1
}
```

**Errors:**
| Status | Condition |
|--------|-----------|
| 400 | `query` is missing or empty |

**Example:**
```bash
curl -X POST http://localhost:3001/retrieve \
  -H "Content-Type: application/json" \
  -d '{"query": "database", "filters": {"mood": "indicative"}}'
```

---

### Synthesis

#### `POST /synthesize`

**Purpose:** Performs RAG (retrieval-augmented generation) by synthesizing an answer from retrieved clauses.

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `query` | string | Yes | - | The query to answer |
| `filters` | object | No | `{}` | Same filter keys as `/retrieve` (`RetrievalFilters`), passed as a symbolized hash to the synthesizer |
| `limit` | integer | No | `10` | Max clauses to retrieve for context |
| `include_fallback` | boolean | No | `false` | Fall back to general LLM knowledge if context misses |
| `expand_ancestors` | boolean | No | `false` | Expand retrieved child clauses to their parents |

**Response (200):**
```json
{
  "query": "What is the database?",
  "answer": "The database is PostgreSQL.",
  "cited_clause_ids": ["clause-uuid"],
  "clauses": [ /* Array of RetrievalResult hashes (not AnnotatedClause) */ ],
  "retrieved_count": 1,
  "confidence": 0.95
}
```

**Errors:**
| Status | Condition |
|--------|-----------|
| 400 | `query` is missing or empty |

**Example:**
```bash
curl -X POST http://localhost:3001/synthesize \
  -H "Content-Type: application/json" \
  -d '{"query": "How does the pipeline work?"}'
```

---

### Clause Management

#### `GET /clauses`

**Purpose:** Lists and filters persisted clauses.

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `document_id` | string | No | - | Filter by document ID |
| `annotation_source` | string | No | - | Filter by source (e.g., llm, spacy) |
| `limit` | integer | No | `50` | Pagination limit |
| `offset` | integer | No | `0` | Pagination offset |
| `source_type` | string | No | - | Filter by source type |
| `mood` | string | No | - | Filter by mood |
| `process_type`| string | No | - | Filter by process type |
| `min_modality`| float | No | - | Filter minimum modality |
| `max_modality`| float | No | - | Filter maximum modality |
| `min_tenor` | float | No | - | Filter minimum tenor |
| `max_tenor` | float | No | - | Filter maximum tenor |

**Response (200):**
```json
{
  "clauses": [ /* Array of AnnotatedClause (Wire format) */ ],
  "total": 100,
  "limit": 50,
  "offset": 0
}
```

**Example:**
```bash
curl -X GET "http://localhost:3001/clauses?document_id=doc-uuid&limit=10"
```

#### `GET /clauses/review-queue`

**Purpose:** Gets the paginated annotation review queue (audit log of accepted/rejected annotations).

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `limit` | integer | No | `50` | Pagination limit |
| `offset` | integer | No | `0` | Pagination offset |

**Response (200):**
```json
{
  "clauses": [ /* Array of clause review rows */ ],
  "total": 5,
  "limit": 50,
  "offset": 0
}
```

**Example:**
```bash
curl -X GET "http://localhost:3001/clauses/review-queue"
```

#### `POST /clauses/:id/review`

**Purpose:** Submit a review decision for a specific annotated clause's annotation quality.

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `decision` | string | Yes | - | enum: `accepted`, `rejected`, `re_annotated` |
| `reviewer` | string | No | - | Identifier of the reviewer |
| `notes` | string | No | - | Optional context for the decision |

**Response (200):** Review record (Wire format)

**Errors:**
| Status | Condition |
|--------|-----------|
| 400 | `decision` is invalid |
| 404 | Clause not found |

**Example:**
```bash
curl -X POST http://localhost:3001/clauses/clause-uuid/review \
  -H "Content-Type: application/json" \
  -d '{"decision": "accepted", "reviewer": "admin"}'
```

---

### Content Review

#### `GET /review-queue`

**Purpose:** Gets pending content reviews (quarantined generated text pending human approval).

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `modality` | string | No | - | Filter by modality type |
| `limit` | integer | No | `50` | Pagination limit |
| `offset` | integer | No | `0` | Pagination offset |

**Response (200):**
```json
{
  "items": [ /* Array of review queue rows */ ],
  "total": 12,
  "limit": 50,
  "offset": 0
}
```

**Example:**
```bash
curl -X GET "http://localhost:3001/review-queue?limit=10"
```

#### `POST /review-queue/:id/decide`

**Purpose:** Approves, rejects, or edits a pending content review entry.

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `decision` | string | Yes | - | enum: `approve`, `reject`, `edit` |
| `edited_text` | string | Cond. | - | Required if decision is `edit` |
| `reviewer` | string | No | - | Identifier of the reviewer |

**Response (200):**
```json
{
  "review": { /* Updated review queue row */ },
  "clauses": [ /* Output from pipeline compile if decision was edit */ ]
}
```

**Errors:**
| Status | Condition |
|--------|-----------|
| 400 | `decision` is invalid, or `edit` decision lacks `edited_text` |
| 404 | Review item not found |

**Example:**
```bash
curl -X POST http://localhost:3001/review-queue/item-uuid/decide \
  -H "Content-Type: application/json" \
  -d '{"decision": "approve"}'
```

---

### Graph

#### `GET /graph/nodes`

**Purpose:** Fetches clause graph nodes (clauses in the knowledge graph).

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `document_id` | string | No | - | Filter by document ID |

**Response (200):** Array of Nodes (Wire format)

**Example:**
```bash
curl -X GET "http://localhost:3001/graph/nodes?document_id=doc-uuid"
```

#### `GET /graph/edges`

**Purpose:** Fetches structural (parent/child) and semantic neighbor edges for clauses.

**Request:**
| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `document_id` | string | No | - | Filter by document ID |

**Response (200):** Array of Edges (Wire format)

**Example:**
```bash
curl -X GET "http://localhost:3001/graph/edges?document_id=doc-uuid"
```
