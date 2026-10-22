# Candidate loader: YamlDocumentAnalysisLoader

Drafted for: `/home/b08x/Notebook/Daily/assets/2025-11-02 Document Analysis & Images/image-1381-1026.png.meta.yaml`
Confidence: 0.8

## Field mapping

The YAML file contains fields such as 'description', 'model_used', 'evaluation', and 'timestamp'. The 'description' field maps to the 'text' field in the unit, as it contains the main content of the document. The 'timestamp' field maps to the 'sent_at' field in the unit, as it indicates when the document was created or analyzed. The 'speaker' field is set to 'System' as there is no specific speaker mentioned in the document. No existing loader matched because this YAML schema is specific to document analysis and includes fields not present in other loaders.

## Status

**Not registered.** Review `yaml_document_analysis_loader.rb`, then wire it in:
add a `require` and a matching entry in `SFL::Ingest::DeterministicRules` before this
loader runs against real data.
