# frozen_string_literal: true

require "spec_helper"

# Unit coverage for gate G3's AST walker, extracted from LoaderDrafter so
# each method stays under the gate. The LoaderDrafter spec
# pins the gate end to end; this spec pins the walker's node semantics,
# including the COLON2/COLON3 constant-path shapes this Ruby's
# RubyVM::AbstractSyntaxTree produces.
RSpec.describe SFL::Ingest::LoaderDrafter::DeclaredClasses do
  def declared_classes_for(source)
    described_class.of(RubyVM::AbstractSyntaxTree.parse(source))
  end

  it "resolves nested module declarations to full constant paths" do
    source = <<~RUBY
      module SFL
        module Core
          class GenericJsonlChatSource
            def each_unit; end
          end
        end
      end
    RUBY

    expect(declared_classes_for(source)).to eq(["SFL::Core::GenericJsonlChatSource"])
  end

  it "resolves the compact declaration style" do
    source = <<~RUBY
      class SFL::Core::Loaders::TranscriptionLoader
        def each_unit; end
      end
    RUBY

    expect(declared_classes_for(source)).to eq(["SFL::Core::Loaders::TranscriptionLoader"])
  end

  it "threads a compact module namespace into nested classes" do
    expect(declared_classes_for("module Outer::Inner\n  class C; end\nend")).to eq(["Outer::Inner::C"])
  end

  it "resolves top-level :: declarations" do
    expect(declared_classes_for("class ::TopLevel; end")).to eq(["::TopLevel"])
  end

  it "resolves a top-level :: segment inside a compact path" do
    expect(declared_classes_for("class ::Top::Level; end")).to eq(["::Top::Level"])
  end

  it "returns every sibling class under one module, outermost first" do
    source = <<~RUBY
      module M
        class A; end
        class B; end
      end
    RUBY

    expect(declared_classes_for(source)).to eq(["M::A", "M::B"])
  end

  it "does not widen the namespace for a class's own body" do
    expect(declared_classes_for("class A\n  class B; end\nend")).to eq(%w[A B])
  end

  it "walks past non-class declarations and returns [] when none match" do
    source = <<~RUBY
      module SFL
        def helper; end

        class << self
          def meta; end
        end
      end
    RUBY

    expect(declared_classes_for(source)).to eq([])
  end
end
