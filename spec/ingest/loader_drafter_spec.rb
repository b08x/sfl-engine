# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

# A predictor response shaped like DSPy::Predict's typed output struct:
# the drafter only calls #to_h on it and works in symbol-keyed Hashes.
LoaderDraftResponse = Struct.new(:class_name, :ruby_source, :field_mapping_explanation, :confidence,
  keyword_init: true)

RSpec.describe SFL::Ingest::LoaderDrafter do
  let(:tmpdir) { Dir.mktmpdir }
  let(:drafts_dir) { File.join(tmpdir, "docs/ingest-review/candidates") }
  let(:docs_dir) { File.join(tmpdir, "docs/ingest-review") }
  let(:lm) { instance_double(DSPy::LM) }
  let(:predictor) { instance_double(DSPy::Predict) }
  let(:drafter) { described_class.new(lm:, drafts_dir:, docs_dir:, predictor:) }

  # Draft fixtures as plain methods: they are test data, not memoized state,
  # and keeping them out of the let pool stays under the memoized-helper
  # budget for every example group below.
  def valid_source
    <<~RUBY
      # frozen_string_literal: true

      module SFL
        module Core
          module Loaders
            # Drafted from a chat export no registered loader matched.
            class GenericJsonlChatSource
              def each_unit
                yield "speaker", "text", nil
              end
            end
          end
        end
      end
    RUBY
  end

  def compact_source
    <<~RUBY
      # frozen_string_literal: true

      class SFL::Core::Loaders::TranscriptionLoader
        def each_unit
          yield "speaker", "text", nil
        end
      end
    RUBY
  end

  # A second, byte-different but valid draft for the same class name.
  def other_valid_source
    <<~RUBY
      # frozen_string_literal: true

      class SFL::Core::Loaders::GenericJsonlChatSource
        def each_unit
          yield "from", "body", nil
        end
      end
    RUBY
  end

  # The incident 4a53727 shape: a markdown-fenced source that cannot parse.
  def fenced_source
    <<~TEXT
      ```ruby
      module SFL
        module Core
          module Loaders
            class FencedChatSource
              def each_unit; end
            end
          end
        end
      end
      ```
    TEXT
  end

  # Valid class name, wrong declaration: a module where a class is required.
  def misdeclared_source
    <<~RUBY
      # frozen_string_literal: true

      module SFL
        module Core
          module Loaders
            module TranscriptionLoader
              def each_unit; end
            end
          end
        end
      end
    RUBY
  end

  before { allow(predictor).to receive(:call).and_return(response_for) }

  after { FileUtils.remove_entry(tmpdir) }

  def response_for(class_name: "GenericJsonlChatSource", ruby_source: valid_source)
    LoaderDraftResponse.new(class_name:, ruby_source:,
      field_mapping_explanation: "speaker from `from`, text from `body`", confidence: 0.42)
  end

  def quarantine_rb_files
    Dir[File.join(tmpdir, "**", "*.rb")]
  end

  describe "#initialize" do
    it "defaults the quarantine and docs dirs and never points a kwarg into lib/" do
      # DSPy::Predict#configure probes the lm for its schema format; a
      # verified instance_double with that one method stubbed keeps the
      # example offline while exercising the real predictor constructor.
      schema_lm = instance_double(DSPy::LM, schema_format: :json_schema)
      default = described_class.new(lm: schema_lm, predictor: nil)

      expect(default.__send__(:drafts_dir)).to eq("docs/ingest-review/candidates")
      expect(default.__send__(:docs_dir)).to eq("docs/ingest-review")
      params = described_class.instance_method(:initialize).parameters
      expect(params).to include(%i[keyreq lm], %i[key drafts_dir], %i[key docs_dir], %i[key predictor])
      expect(params.map(&:last)).not_to include(:loaders_dir)
    end

    it "keeps the component source free of any reference to the Zeitwerk-loaded tree" do
      expect(File.read("lib/sfl/ingest/loader_drafter.rb")).not_to include("lib/sfl/core/loaders")
    end

    it "keeps the injected lm and predictor seams" do
      expect(drafter.__send__(:lm)).to equal(lm)
      expect(drafter.__send__(:predictor)).to equal(predictor)
    end

    it "builds a real DSPy predictor configured with the lm when none is injected" do
      schema_lm = instance_double(DSPy::LM, schema_format: :json_schema)
      default = described_class.new(lm: schema_lm, predictor: nil)
      predictor = default.__send__(:predictor)

      expect(predictor).to be_a(DSPy::Predict)
      expect(predictor.lm).to equal(schema_lm)
    end
  end

  describe "#draft" do
    it "writes a valid draft into the quarantine and returns the loader/doc path pair" do
      result = drafter.draft("file sample", "chats/messages.jsonl")

      expect(predictor).to have_received(:call).with(file_sample: "file sample", filename: "chats/messages.jsonl")
      expect(result.keys).to contain_exactly(:loader_path, :doc_path)
      expect(result[:loader_path]).to eq(File.join(drafts_dir, "generic_jsonl_chat_source.rb"))
      expect(result[:doc_path]).to eq(File.join(docs_dir, "generic_jsonl_chat_source.md"))
      expect(File.read(result[:loader_path])).to eq(valid_source)
      expect(quarantine_rb_files).to contain_exactly(result[:loader_path])
    end

    it "names the quarantine and the promotion recipe in the review doc, still Not registered" do
      result = drafter.draft("file sample", "chats/messages.jsonl")
      doc = File.read(result[:doc_path])

      expect(doc).to include("# Candidate loader: GenericJsonlChatSource")
      expect(doc).to include("Drafted for: `chats/messages.jsonl`")
      expect(doc).to include("Confidence: 0.42")
      expect(doc).to include("## Field mapping\n\nspeaker from `from`, text from `body`\n\n## Status")
      expect(doc).to include("**Not registered.**")
      expect(doc).to include("quarantine at\n`#{drafts_dir}/` — nothing requires, loads or")
      expect(doc).to include("run `ruby -c` on\n`#{result[:loader_path]}`")
      expect(doc).to include("lib/sfl/core/loaders/generic_jsonl_chat_source.rb")
      expect(doc).to include("SFL::Ingest::DeterministicRules")
      expect(doc).not_to include("INVALID")
    end

    it "accepts the compact declaration style at gate G3" do
      allow(predictor).to receive(:call).and_return(response_for(class_name: "TranscriptionLoader",
        ruby_source: compact_source))

      result = drafter.draft("file sample", "transcripts/tr.jsonl")

      expect(result[:loader_path]).to eq(File.join(drafts_dir, "transcription_loader.rb"))
      expect(File.read(result[:loader_path])).to eq(compact_source)
    end

    it "rejects a malformed class name at gate G1 and writes nothing, as before" do
      allow(predictor).to receive(:call).and_return(response_for(class_name: "transcriptionLoader"))

      expect { drafter.draft("file sample", "a.txt") }
        .to raise_error(SFL::Ingest::LoaderDrafter::Error) do |error|
          # Surfaces directly from write_draft, not re-wrapped by #draft's generic rescue.
          expect(error.message)
            .to start_with('loader draft for a.txt returned an invalid class_name: "transcriptionLoader"')
        end
      expect(Dir[File.join(tmpdir, "**", "*")]).to be_empty
    end

    it "rejects an unparseable fenced source at gate G2 with exactly one predictor call" do
      allow(predictor).to receive(:call).once
        .and_return(response_for(class_name: "FencedChatSource", ruby_source: fenced_source))

      expect { drafter.draft("file sample", "a.md") }
        .to raise_error(SFL::Ingest::LoaderDrafter::Error) do |error|
          # Surfaces directly from record_invalid, not re-wrapped by #draft's generic rescue.
          expect(error.message).to start_with("loader draft for a.md failed gate G2 (syntax parse)")
        end
      expect(quarantine_rb_files).to be_empty

      doc = File.read(File.join(docs_dir, "fenced_chat_source-invalid.md"))
      expect(doc).to include("# Invalid loader draft: FencedChatSource")
      expect(doc).to include("Drafted for: `a.md`")
      expect(doc).to include("INVALID — do not promote")
      expect(doc).to include("G2 (syntax parse)")
      # The reason is the parser's own message, rendered as text rather than a Ruby dump.
      expect(doc).to include("syntax error, unexpected backtick literal")
      expect(doc).not_to include("#<")
      expect(doc).to include(fenced_source)
    end

    it "rejects a misdeclared constant at gate G3 and writes only the evidence doc" do
      allow(predictor).to receive(:call)
        .and_return(response_for(class_name: "TranscriptionLoader", ruby_source: misdeclared_source))

      expect { drafter.draft("file sample", "t.txt") }
        .to raise_error(SFL::Ingest::LoaderDrafter::Error) do |error|
          expect(error.message).to start_with("loader draft for t.txt failed gate G3 (declared class name)")
          expect(error.message)
            .to include("for SFL::Core::Loaders::TranscriptionLoader: it declares [], " \
              "not SFL::Core::Loaders::TranscriptionLoader")
        end
      expect(quarantine_rb_files).to be_empty

      doc = File.read(File.join(docs_dir, "transcription_loader-invalid.md"))
      expect(doc).to include("# Invalid loader draft: TranscriptionLoader")
      expect(doc).to include("Drafted for: `t.txt`")
      expect(doc).to include("INVALID — do not promote")
      expect(doc).to include("it declares [], not SFL::Core::Loaders::TranscriptionLoader")
      expect(doc).to include(misdeclared_source)
    end

    it "never lets an invalid draft overwrite a valid draft's files" do
      drafter.draft("file sample", "chats/messages.jsonl")
      allow(predictor).to receive(:call)
        .and_return(response_for(class_name: "GenericJsonlChatSource", ruby_source: fenced_source))

      expect { drafter.draft("file sample", "chats/messages.jsonl") }
        .to raise_error(SFL::Ingest::LoaderDrafter::Error, /G2 \(syntax parse\)/)

      expect(File.read(File.join(drafts_dir, "generic_jsonl_chat_source.rb"))).to eq(valid_source)
      expect(File.read(File.join(docs_dir, "generic_jsonl_chat_source.md"))).to include("**Not registered.**")
    end

    it "returns the existing paths untouched on a byte-identical re-draft" do
      first = drafter.draft("file sample", "chats/messages.jsonl")

      expect(drafter.draft("file sample", "chats/messages.jsonl")).to eq(first)
      expect(File.read(first[:loader_path])).to eq(valid_source)
      expect(File.read(first[:doc_path])).to include("**Not registered.**")
      expect(Dir[File.join(drafts_dir, "*")]).to contain_exactly(first[:loader_path])
    end

    it "raises DuplicateDraftError on a differing re-draft and writes nothing" do
      first = drafter.draft("file sample", "chats/messages.jsonl")
      allow(predictor).to receive(:call)
        .and_return(response_for(class_name: "GenericJsonlChatSource", ruby_source: other_valid_source))

      expect { drafter.draft("file sample", "chats/messages.jsonl") }
        .to raise_error(SFL::Ingest::LoaderDrafter::DuplicateDraftError, /nothing was written/)
      expect(File.read(first[:loader_path])).to eq(valid_source)
      expect(Dir[File.join(drafts_dir, "*")]).to contain_exactly(first[:loader_path])
    end

    it "wraps a predictor failure in Error and writes no files" do
      allow(predictor).to receive(:call).and_raise(Timeout::Error, "llm timeout")

      expect { drafter.draft("file sample", "chats/messages.jsonl") }
        .to raise_error(SFL::Ingest::LoaderDrafter::Error,
          "loader draft failed for chats/messages.jsonl: llm timeout")
      expect(Dir[File.join(tmpdir, "**", "*")]).to be_empty
    end

    it "reports the predictor exception's message, not its to_s form" do
      loud = Class.new(StandardError) do
        def message = "the reported reason"
      end
      allow(predictor).to receive(:call).and_raise(loud.new("the to_s form"))

      expect { drafter.draft("file sample", "chats/messages.jsonl") }
        .to raise_error(SFL::Ingest::LoaderDrafter::Error,
          "loader draft failed for chats/messages.jsonl: the reported reason")
    end

    it "symbolizes a string-keyed predictor response before the gates" do
      string_keyed = Object.new
      def string_keyed.to_h
        {
          "class_name" => "GenericJsonlChatSource",
          "ruby_source" => "class SFL::Core::Loaders::GenericJsonlChatSource\n  def each_unit; end\nend\n",
          "field_mapping_explanation" => "speaker from `from`, text from `body`",
          "confidence" => 0.42,
        }
      end
      allow(predictor).to receive(:call).and_return(string_keyed)

      result = drafter.draft("file sample", "chats/messages.jsonl")

      expect(result[:loader_path]).to eq(File.join(drafts_dir, "generic_jsonl_chat_source.rb"))
      expect(File.read(result[:doc_path])).to include("Confidence: 0.42")
    end

    it "underscores digit-to-uppercase boundaries when naming the quarantined file" do
      allow(predictor).to receive(:call)
        .and_return(response_for(class_name: "Markdown2Html",
          ruby_source: "class SFL::Core::Loaders::Markdown2Html\n  def each_unit; end\nend\n"))

      expect(drafter.draft("file sample", "x.md")[:loader_path])
        .to eq(File.join(drafts_dir, "markdown2_html.rb"))
    end

    it "creates the docs dir itself when it does not sit inside the drafts dir" do
      separate = described_class.new(lm:, drafts_dir: File.join(tmpdir, "quarantine"),
        docs_dir: File.join(tmpdir, "review"), predictor:)

      result = separate.draft("file sample", "chats/messages.jsonl")

      expect(result[:loader_path]).to eq(File.join(tmpdir, "quarantine", "generic_jsonl_chat_source.rb"))
      expect(File.file?(result[:loader_path])).to be(true)
      expect(File.file?(File.join(tmpdir, "review", "generic_jsonl_chat_source.md"))).to be(true)
    end
  end

  # The quarantine feature's "corpus of four" incident shape: one drafter
  # instance sees four incident-shaped samples in one run - one that merely
  # references undefined constants (still inert data, so quarantined), one
  # markdown-fenced blob, and two misnamed modules - and must leave a
  # quarantine that grows only for new class names.
  describe "incident-shaped corpus of four drafts" do
    # Compact style, parses, declares the requested class - but calls helper
    # constants that exist nowhere. The gates are syntactic, not semantic:
    # no repair, no retry, the draft is quarantined as-is.
    def undefined_refs_source
      <<~RUBY
        # frozen_string_literal: true

        class SFL::Core::Loaders::ChatDigestSource
          def each_unit
            yield UndefinedHelper.speaker(row), row.fetch("body"), nil
          end
        end
      RUBY
    end

    # Nested style declaring a class name that does not match the one the
    # predictor claimed: rejected at G3 like the misdeclared module.
    def renamed_source
      <<~RUBY
        # frozen_string_literal: true

        module SFL
          module Core
            module Loaders
              class TranscriptionLoader
                def each_unit; end
              end
            end
          end
        end
      RUBY
    end

    def corpus_responses
      [
        response_for(class_name: "ChatDigestSource", ruby_source: undefined_refs_source),
        response_for(class_name: "FencedChatSource", ruby_source: fenced_source),
        response_for(class_name: "TranscriptionLoader", ruby_source: misdeclared_source),
        response_for(class_name: "DigestLoader", ruby_source: renamed_source),
      ]
    end

    before { allow(predictor).to receive(:call).and_return(*corpus_responses) }

    def run_corpus
      [
        ["digest sample", "chats/digest.jsonl"],
        ["fenced blob", "notes/blob.md"],
        ["module not class", "transcripts/t.txt"],
        ["renamed constant", "misc/d.txt"],
      ].each do |sample, path|
        drafter.draft(sample, path)
      rescue SFL::Ingest::LoaderDrafter::Error
        nil
      end
    end

    it "quarantines the one gate-passing draft and rejects the other three" do
      expect(drafter.draft("digest sample", "chats/digest.jsonl")[:loader_path])
        .to eq(File.join(drafts_dir, "chat_digest_source.rb"))
      expect { drafter.draft("fenced blob", "notes/blob.md") }
        .to raise_error(SFL::Ingest::LoaderDrafter::Error, /G2 \(syntax parse\)/)
      expect { drafter.draft("module not class", "transcripts/t.txt") }
        .to raise_error(SFL::Ingest::LoaderDrafter::Error, /G3 \(declared class name\)/)
      expect { drafter.draft("renamed constant", "misc/d.txt") }
        .to raise_error(SFL::Ingest::LoaderDrafter::Error, /G3 \(declared class name\)/)

      expect(quarantine_rb_files).to contain_exactly(File.join(drafts_dir, "chat_digest_source.rb"))
    end

    it "accumulates no suffixed junk: one quarantine draft plus one evidence doc per rejection" do
      run_corpus

      expect(Dir[File.join(drafts_dir, "*")]).to contain_exactly(File.join(drafts_dir, "chat_digest_source.rb"))
      expect(Dir[File.join(docs_dir, "*")].select { |f| File.file?(f) }).to contain_exactly(
        File.join(docs_dir, "chat_digest_source.md"),
        File.join(docs_dir, "fenced_chat_source-invalid.md"),
        File.join(docs_dir, "transcription_loader-invalid.md"),
        File.join(docs_dir, "digest_loader-invalid.md")
      )
      expect(Dir[File.join(tmpdir, "**", "*")].map { |f| File.basename(f) })
        .to all(satisfy { |name| !name.match?(/-invalid-|\(\d\)|\.bak|~/) })
    end

    it "grows the quarantine only for new class names" do
      run_corpus

      allow(predictor).to receive(:call).and_return(corpus_responses.first)
      expect(drafter.draft("digest sample", "chats/digest.jsonl")[:loader_path])
        .to eq(File.join(drafts_dir, "chat_digest_source.rb"))
      expect(Dir[File.join(drafts_dir, "*")]).to contain_exactly(File.join(drafts_dir, "chat_digest_source.rb"))

      allow(predictor).to receive(:call)
        .and_return(response_for(class_name: "TranscriptionLoader", ruby_source: compact_source))
      expect(drafter.draft("compact sample", "transcripts/tr.jsonl")[:loader_path])
        .to eq(File.join(drafts_dir, "transcription_loader.rb"))
      expect(Dir[File.join(drafts_dir, "*")]).to contain_exactly(
        File.join(drafts_dir, "chat_digest_source.rb"),
        File.join(drafts_dir, "transcription_loader.rb")
      )
    end
  end

  describe "error hierarchy" do
    it "keeps both errors under SFL::Error via LoaderDrafter::Error" do
      expect(described_class::DuplicateDraftError.superclass).to be(described_class::Error)
      expect(described_class::Error.superclass).to be(SFL::Error)
    end
  end
end
