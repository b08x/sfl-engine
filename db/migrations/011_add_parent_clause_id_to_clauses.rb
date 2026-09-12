# frozen_string_literal: true

# Parent/child contextual chunking (card: "Refactor DB schema for
# parent/child contextual chunking"): a "child chunk" is just a `clauses`
# row whose `parent_clause_id` points at another `clauses` row's
# `external_id` — reuses PgClauseStore/ClauseFilters/AnnotatedClause as-is
# rather than introducing a parallel `chunks` table.
#
# Direct self-reference is blocked by a CHECK constraint. Multi-level
# cycles (A -> B -> A) can't be expressed by a CHECK (each row only sees
# its own columns), so a BEFORE INSERT OR UPDATE trigger walks the
# ancestor chain and raises before it would revisit the row being written.
#
# Also adds readability metadata (Lingua::EN::Readability scores via
# Analysis::ReadabilityScorer) as plain nullable columns on the same row —
# every clause gets scored, not just chunks with children, so these live
# alongside `parent_clause_id` rather than in a separate table.
Sequel.migration do
  up do
    alter_table(:clauses) do
      add_column :parent_clause_id, String
      add_column :readability_flesch, Float
      add_column :readability_kincaid, Float
      add_column :readability_fog, Float
      add_column :word_count, Integer

      add_index :parent_clause_id
      add_foreign_key [:parent_clause_id], :clauses,
        key: :external_id, on_delete: :cascade, name: :fk_clauses_parent_clause_id

      add_constraint(:chk_clauses_parent_not_self) do
        Sequel.lit("parent_clause_id IS NULL OR parent_clause_id <> external_id")
      end
    end

    run <<~SQL
      CREATE OR REPLACE FUNCTION clauses_prevent_cycle() RETURNS trigger AS $$
      DECLARE
        visited text[] := ARRAY[NEW.external_id];
        current_parent text := NEW.parent_clause_id;
      BEGIN
        IF NEW.parent_clause_id IS NULL THEN
          RETURN NEW;
        END IF;

        WHILE current_parent IS NOT NULL LOOP
          IF current_parent = ANY(visited) THEN
            RAISE EXCEPTION 'clauses.parent_clause_id would introduce a cycle at %', current_parent;
          END IF;
          visited := array_append(visited, current_parent);
          SELECT parent_clause_id INTO current_parent FROM clauses WHERE external_id = current_parent;
        END LOOP;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL

    run <<~SQL
      CREATE TRIGGER clauses_prevent_cycle_trigger
        BEFORE INSERT OR UPDATE OF parent_clause_id ON clauses
        FOR EACH ROW
        WHEN (NEW.parent_clause_id IS NOT NULL)
        EXECUTE FUNCTION clauses_prevent_cycle();
    SQL
  end

  down do
    run "DROP TRIGGER IF EXISTS clauses_prevent_cycle_trigger ON clauses;"
    run "DROP FUNCTION IF EXISTS clauses_prevent_cycle();"

    alter_table(:clauses) do
      drop_constraint :chk_clauses_parent_not_self
      drop_foreign_key [:parent_clause_id], name: :fk_clauses_parent_clause_id
      drop_column :parent_clause_id
      drop_column :readability_flesch
      drop_column :readability_kincaid
      drop_column :readability_fog
      drop_column :word_count
    end
  end
end
