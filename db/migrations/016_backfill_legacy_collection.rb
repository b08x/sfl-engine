# frozen_string_literal: true

# Backfills clauses stored before collections existed into a collection named
# `legacy`: one document per distinct section id prefix before `#`, and one
# section per distinct clause section id. A section whose suffix is `turn-N`
# gets kind `turn`; every other section gets kind `unknown`. A section id
# without `#` becomes a document with one section. The `legacy` data is
# disposable (`rake db:purge_collection[legacy]`), so no effort goes into
# recovering heading structure.
Sequel.migration do
  up do
    run <<~SQL
      INSERT INTO collections (name)
      SELECT 'legacy'
      WHERE EXISTS (SELECT 1 FROM clauses WHERE section_id IS NOT NULL)
        AND NOT EXISTS (SELECT 1 FROM collections WHERE lower(name) = 'legacy')
    SQL

    run <<~SQL
      INSERT INTO documents (collection_id, document_key, source_path, title, source_type, ingested_at, updated_at)
      SELECT (SELECT id FROM collections WHERE lower(name) = 'legacy'),
             split_part(section_id, '#', 1), split_part(section_id, '#', 1), split_part(section_id, '#', 1),
             max(source_type), min(created_at), now()
      FROM clauses
      WHERE section_id IS NOT NULL
      GROUP BY split_part(section_id, '#', 1)
      ON CONFLICT (document_key) DO NOTHING
    SQL

    run <<~SQL
      INSERT INTO sections (section_id, document_id, ordinal, kind, clause_count, updated_at)
      SELECT grouped.section_id, documents.id,
             row_number() OVER (PARTITION BY documents.id ORDER BY grouped.first_clause),
             CASE WHEN grouped.section_id ~ '#turn-[0-9]+$' THEN 'turn' ELSE 'unknown' END,
             grouped.clause_count, now()
      FROM (
        SELECT section_id, min(id) AS first_clause, count(*) AS clause_count
        FROM clauses
        WHERE section_id IS NOT NULL
        GROUP BY section_id
      ) AS grouped
      JOIN documents ON documents.document_key = split_part(grouped.section_id, '#', 1)
      ON CONFLICT (section_id) DO NOTHING
    SQL

    run <<~SQL
      UPDATE documents
      SET section_count = (SELECT count(*) FROM sections WHERE sections.document_id = documents.id)
      WHERE collection_id = (SELECT id FROM collections WHERE lower(name) = 'legacy')
    SQL
  end

  down do
    run "DELETE FROM collections WHERE lower(name) = 'legacy'"
  end
end
