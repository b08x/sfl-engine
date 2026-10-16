# frozen_string_literal: true

module SFL
  module Eval
    # The 14 narrative dataset items (decisions.md Q4/Q6) as report-file paths.
    # Items 11-14 are unseen conversations whose reports are produced by a
    # pipeline run with the pinned Pass 2 model into +eval_dir+/nd-<n>/.
    module NarrativeSources
      REPORT = "conversation_analysis.json"

      # @param engine_output [String] sfl-engine output/ directory
      # @param compiler_output [String] sfl-compiler output/ directory
      # @param eval_dir [String] where items 11-14 reports were written
      # @return [Array<NarrativeDatasetBuilder::Source>]
      module_function def catalog(engine_output:, compiler_output:, eval_dir:)
        source = NarrativeDatasetBuilder::Source
        steve = File.join(compiler_output, "steve-oliver-analysis", REPORT)
        [
          source.new(item_no: 1, path: File.join(engine_output, "ass011", REPORT), source: "engine:ass011", genre: "chat"),
          source.new(item_no: 2, path: File.join(engine_output, "ass012", REPORT), source: "engine:ass012", genre: "chat"),
          source.new(item_no: 3, path: File.join(compiler_output, "ass01", REPORT), source: "compiler:ass01", genre: "chat"),
          source.new(item_no: 4, path: File.join(compiler_output, "notebooklm", REPORT), source: "compiler:notebooklm", genre: "monologue"),
          source.new(item_no: 5, path: File.join(compiler_output, "sillytavern_group_chats_v9", REPORT),
            source: "compiler:sillytavern_group_chats_v9", genre: "roleplay-group"),
          source.new(item_no: 6, path: steve, source: "compiler:steve-oliver-analysis", genre: "meeting"),
          source.new(item_no: 7, path: File.join(compiler_output, "sfl-halo-output", REPORT), source: "compiler:sfl-halo-output", genre: "chat"),
          source.new(item_no: 8, path: File.join(compiler_output, "sillytavernRacistBreakfast", REPORT),
            source: "compiler:sillytavernRacistBreakfast", genre: "roleplay-hostile"),
          source.new(item_no: 9, path: File.join(compiler_output, "latest0009", REPORT), source: "compiler:latest0009",
            genre: "chat", probe: :low_confidence),
          source.new(item_no: 10, path: steve, source: "compiler:steve-oliver-analysis (3 rows defaulted)",
            genre: "meeting", probe: :unreliable),
          *unseen(eval_dir),
        ]
      end

      module_function def unseen(eval_dir)
        [
          [11, "The_Real_AI_Threat_Is_Human_Paranoia_nlp.jsonl", "chat"],
          [12, "claude-export:c05dd4f6 Demonstrating Expertise to Doubtful Clients", "chat"],
          [13, "chatgpt-export:6926a4c2 Branch - Hedgingly as a phrase", "chat"],
          [14, "mistral-export:aca44f91 aberrant salience and AI psychosis", "chat"],
        ].map do |number, label, genre|
          NarrativeDatasetBuilder::Source.new(item_no: number, path: File.join(eval_dir, "nd-#{number}", REPORT),
            source: label, genre:)
        end
      end
    end
  end
end
