# Candidate loader: YamlDocumentAnalysisLoader

Drafted for: `/home/b08x/Notebook/Daily/assets/2025-11-02 Document Analysis & Images/image-1381-1026.png.meta.yaml`
Confidence: 0.8

## Field mapping

The YAML file contains fields such as 'description', 'model_used', 'evaluation', and 'timestamp'. The 'description' field maps to the 'text' field in the unit, as it contains the main content of the document. The 'timestamp' field maps to the 'sent_at' field in the unit, as it indicates when the document was created or analyzed. The 'speaker' field is set to 'System' as there is no specific speaker mentioned in the document. No existing loader matched because this YAML schema is specific to document analysis and includes fields not present in other loaders.

## Status

**Superseded by `SFL::Core::Loaders::ImageMetaSource`** at
`lib/sfl/core/loaders/image_meta_source.rb`. The draft file
`yaml_document_analysis_loader.rb` this doc accompanied was removed and replaced by that
production loader. Corrected field mapping (one unit per file): `text` from `description`,
`sent_at` from `timestamp` (nil with a single warning when missing or unparseable), and
attribution in metadata (`model_used` / `evaluation`) instead of a fabricated "System" speaker;
`speaker` is nil. The YAML is parsed with the safe parser only, so `!ruby/object` tags are
rejected without instantiating anything.

Registered: files whose basename matches `image-*.meta.yaml` route deterministically via
`SFL::Ingest::DeterministicRules` to source_type `vault_image_meta`, which the ingest
orchestrator resolves to the `:image_meta` factory in `Core::Loaders::Catalog`. Ordinary
`.yaml`/`.meta.yaml` files are unaffected — they still fall through to the classifier.

Behavior is proven by `spec/core/loaders/image_meta_source_spec.rb`.
