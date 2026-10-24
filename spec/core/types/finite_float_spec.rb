# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Types::FiniteFloat do
  # module_function gives every method two identities: a private instance
  # method on this module, and a public copy on the singleton made at
  # definition time. Production code (the 9 guarded type files) calls the
  # singleton copy; mutant's subject matcher only sees the instance-level
  # methods, and its fork redefines those — the singleton copy, already
  # frozen at load time, is unreachable for it (a direct
  # `described_class.send(...)` resolves through the singleton class and so
  # never observes a mutant either). The lets below build types through an
  # instance of a shim class that includes the module: method lookup on the
  # shim has no singleton copy in the way, so every example observes exactly
  # the code mutant mutates. The "public module method" examples pin the
  # singleton copy the guarded types actually use.
  let(:shim) do
    mod = described_class
    Class.new { include mod }.new
  end
  let(:fraction) { build_constrained(SFL::Core::Types::Float, gteq: 0.0, lteq: 1.0) }
  let(:coercible_fraction) { build_constrained(SFL::Core::Types::Coercible::Float, gteq: 0.0, lteq: 1.0) }

  def build_constrained(base, **bounds)
    shim.__send__(:constrained, base, **bounds)
  end

  describe ".constrained" do
    it "accepts finite floats inside the bounds, including both boundaries" do
      expect(fraction.call(0.0)).to eq(0.0)
      expect(fraction.call(0.5)).to eq(0.5)
      expect(fraction.call(1.0)).to eq(1.0)
    end

    it "still rejects finite floats outside the bounds" do
      expect { fraction.call(1.5) }.to raise_error(Dry::Types::ConstraintError)
      expect { fraction.call(-0.25) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "coerces a bare Integer boundary value on the Coercible base" do
      expect(coercible_fraction.call(1)).to eq(1.0)
      expect(coercible_fraction.call(0)).to eq(0.0)
    end

    it "rejects NaN with ConstraintError (gteq/lteq are complement-of-strict, so bare constrained passes it)" do
      expect { fraction.call(Float::NAN) }.to raise_error(Dry::Types::ConstraintError)
      expect { coercible_fraction.call(Float::NAN) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "rejects +Infinity even on a gteq-only bound" do
      unbounded = build_constrained(SFL::Core::Types::Float, gteq: 0.0)

      expect(unbounded.call(12.5)).to eq(12.5)
      expect { unbounded.call(Float::INFINITY) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "rejects -Infinity" do
      expect { fraction.call(-Float::INFINITY) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "keeps nil valid through .optional" do
      expect(fraction.optional.call(nil)).to be_nil
    end

    it "honours every dry-logic bound shape it accepts" do
      expect(build_constrained(SFL::Core::Types::Float, gt: 0.0, lt: 1.0).call(0.5)).to eq(0.5)
      expect { build_constrained(SFL::Core::Types::Float, gt: 0.0, lt: 1.0).call(0.0) }
        .to raise_error(Dry::Types::ConstraintError)
    end

    it "rejects a non-numeric String with the base's typed ConstraintError (type? runs before the finite rule)" do
      expect { fraction.call("7.25") }.to raise_error(Dry::Types::ConstraintError, /type\?\(Float/)
    end

    it "rejects an uncoercible String on the Coercible base with the typed CoercionError Float coercion gives" do
      expect { coercible_fraction.call("high") }.to raise_error(Dry::Types::CoercionError, /Float/)
    end

    it "public module method builds an equivalent guard (the API the 9 guarded type files call)" do
      public_fraction = described_class.constrained(SFL::Core::Types::Float, gteq: 0.0, lteq: 1.0)

      expect(public_fraction.call(0.5)).to eq(0.5)
      expect { public_fraction.call(1.5) }.to raise_error(Dry::Types::ConstraintError)
      expect { public_fraction.call(Float::NAN) }.to raise_error(Dry::Types::ConstraintError)
      expect { public_fraction.call(Float::INFINITY) }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe ".value" do
    let(:element) { shim.__send__(:value, SFL::Core::Types::Float) }

    it "accepts any finite float and rejects NaN and +/-Infinity" do
      expect(element.call(7.25)).to eq(7.25)
      expect(element.call(-0.0)).to eq(-0.0)

      expect { element.call(Float::NAN) }.to raise_error(Dry::Types::ConstraintError)
      expect { element.call(Float::INFINITY) }.to raise_error(Dry::Types::ConstraintError)
      expect { element.call(-Float::INFINITY) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "does not coerce: an Integer is rejected even though Integer#finite? is true" do
      expect { element.call(1) }.to raise_error(Dry::Types::ConstraintError)
    end

    it "rejects non-numeric input with the same typed ConstraintError a plain Float type gives (regression: NoMethodError)" do
      expect { element.call("7.25") }.to raise_error(Dry::Types::ConstraintError, /type\?\(Float/)
      expect { element.call(nil) }.to raise_error(Dry::Types::ConstraintError, /type\?\(Float/)
    end

    it "keeps nil valid through .optional" do
      expect(element.optional.call(nil)).to be_nil
    end

    it "public module method builds an equivalent guard" do
      public_element = described_class.value(SFL::Core::Types::Float)

      expect(public_element.call(7.25)).to eq(7.25)
      expect { public_element.call(Float::NAN) }.to raise_error(Dry::Types::ConstraintError)
      expect { public_element.call(Float::INFINITY) }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe "#finite? (the predicate behind FINITE_RULE)" do
    it "answers true only for finite floats" do
      expect(shim.__send__(:finite?, 0.0)).to be(true)
      expect(shim.__send__(:finite?, -1.5e300)).to be(true)
    end

    it "answers false for NaN and +/-Infinity" do
      expect(shim.__send__(:finite?, Float::NAN)).to be(false)
      expect(shim.__send__(:finite?, Float::INFINITY)).to be(false)
      expect(shim.__send__(:finite?, -Float::INFINITY)).to be(false)
    end
  end

  # Every constrained float type the verifier flagged must reject NaN.
  # dry-struct surfaces the underlying ConstraintError as Dry::Struct::Error,
  # so both are asserted via their shared parent, Dry::Types::CoercionError.
  describe "the guarded types" do
    it "rejects NaN on the 0..1 aggregates (CohesionMetrics, ConversationTurn, KnowledgeArtifact)" do
      aggregate_failures do
        expect_nan_rejected { SFL::Core::Types::CohesionMetrics.new(repetition_score: Float::NAN) }
        expect_nan_rejected do
          SFL::Core::Types::ConversationTurn.new(
            turn_id: 1, speaker: "Alice", timestamp: Time.now, message_text: "text",
            clauses: [], avg_tenor: Float::NAN, avg_modality: 0.5, dominant_mood: "declarative"
          )
        end
        expect_nan_rejected do
          SFL::Core::Types::KnowledgeArtifact.new(
            artifact_id: 1, title: "t", source_file: "f", content_type: :unknown,
            quality_score: Float::NAN, migration_action: :review, dominant_mood: "declarative",
            avg_tenor: 0.5, avg_modality: 0.5
          )
        end
      end
    end

    it "rejects NaN on the quality/confidence scores (MigrationManifestEntry, ReasoningTrace, ClassificationResult)" do
      aggregate_failures do
        expect_nan_rejected do
          SFL::Core::Types::MigrationManifestEntry.new(
            artifact_id: 1, title: "t", source_file: "f", action: :review,
            reason: "r", quality_score: Float::NAN, content_type: :unknown
          )
        end
        expect_nan_rejected do
          SFL::Core::Types::ReasoningTrace.new(
            premises: [], inference_rule: "r", conclusion: {}, confidence: Float::NAN,
            derivation_hash: "h", generated_at: Time.now
          )
        end
        expect_nan_rejected do
          SFL::Core::Types::ClassificationResult.new(
            format: "markdown", mode: nil, confidence: Float::NAN, reasoning: "r"
          )
        end
      end
    end

    it "rejects NaN on SpeakerProfile's aggregates and the ModalityWeight/TenorValue constants" do
      aggregate_failures do
        expect_nan_rejected do
          SFL::Core::Types::SpeakerProfile.new(speaker_name: "Alice", turn_count: 1, avg_tenor: Float::NAN)
        end
        expect_nan_rejected do
          SFL::Core::Types::SpeakerProfile.new(speaker_name: "Alice", turn_count: 1, tenor_variance: Float::NAN)
        end
        expect_nan_rejected { SFL::Core::Types::ModalityWeight.call(Float::NAN) }
        expect_nan_rejected { SFL::Core::Types::TenorValue.call(Float::NAN) }
      end
    end

    it "rejects NaN inside SpeakerProfile#tenor_range's float elements" do
      expect_nan_rejected do
        SFL::Core::Types::SpeakerProfile.new(
          speaker_name: "Alice", turn_count: 1, tenor_range: [Float::NAN, 0.5]
        )
      end
    end

    it "rejects a non-numeric String inside SpeakerProfile#tenor_range with the pre-guard typed error" do
      expect do
        SFL::Core::Types::SpeakerProfile.new(
          speaker_name: "Alice", turn_count: 1, tenor_range: ["7.25", 0.5]
        )
      end.to raise_error(Dry::Struct::Error, /tenor_range/)
    end

    it "accepts the same structs with finite in-range floats and nil optionals" do
      profile = SFL::Core::Types::SpeakerProfile.new(
        speaker_name: "Alice", turn_count: 1, avg_tenor: nil,
        tenor_range: [0.1, 0.9], tenor_variance: nil, avg_modality: 0.4
      )

      expect(profile.avg_tenor).to be_nil
      expect(profile.tenor_range).to eq([0.1, 0.9])
      expect(profile.tenor_variance).to be_nil
    end

    it "keeps Types::Readability accepting nil and finite floats (its own contract, untouched)" do
      readability = SFL::Core::Types::Readability.new(flesch: 63.9, kincaid: 7.5, fog: 11.4, word_count: 5)
      nils = SFL::Core::Types::Readability.new

      expect(readability.flesch).to eq(63.9)
      expect(nils.flesch).to be_nil
    end

    private def expect_nan_rejected(&)
      expect(&).to raise_error(Dry::Types::CoercionError, /NaN/)
    end
  end
end
