# frozen_string_literal: true

require "spec_helper"
# Analysis::NarrativeGenerator#generate names Dry::Struct::Error in a rescue clause.
require "dry-struct"

RSpec.describe SFL::LLM::Narrators::SectionParser do
  let(:full_text) do
    <<~TEXT
      Preamble the model should not have written.

      ## Overview
      A two-person planning call.

      ## Cast and roles
      Robert gives the instructions; Ana answers them.

      **Interpersonal dynamics:**
      Imperatives run one way.

      ### Conversational arc
      Opens on scheduling, pivots at turn 4.

      ## Data quality
      Turns 7-9 are unmeasured.

      ## Takeaways
      Robert holds the facilitator role.
    TEXT
  end

  it "returns one String per section key, in SECTIONS order" do
    sections = described_class.call(full_text)

    expect(sections.keys).to eq(described_class::SECTIONS.keys)
    expect(sections.values).to all(be_a(String))
  end

  it "keeps each body up to the next heading, with surrounding whitespace stripped" do
    sections = described_class.call(full_text)

    expect(sections).to include(
      overview: "A two-person planning call.",
      cast_and_roles: "Robert gives the instructions; Ana answers them.",
      interpersonal_dynamics: "Imperatives run one way.",
      conversational_arc: "Opens on scheduling, pivots at turn 4.",
      data_quality: "Turns 7-9 are unmeasured.",
      takeaways: "Robert holds the facilitator role."
    )
  end

  it "keeps multi-line bodies intact" do
    text = "## Overview\nLine one.\nLine two.\n\n## Cast and roles\nx\n## Interpersonal dynamics\nx\n" \
      "## Conversational arc\nx\n## Data quality\nx\n## Takeaways\nx\n"

    expect(described_class.call(text)[:overview]).to eq("Line one.\nLine two.")
  end

  it "accepts the heading spelled with underscores or capitals, as the model may write it" do
    text = "## cast_and_roles\nA\n## OVERVIEW\nB\n## Interpersonal Dynamics\nC\n## conversational arc\nD\n" \
      "## Data Quality\nE\n## Takeaways\nF\n"

    expect(described_class.call(text).values).to eq(%w[B A C D E F])
  end

  it "raises MissingSectionsError naming every absent section" do
    expect { described_class.call("## Overview\nOnly this.\n") }.to raise_error(
      SFL::LLM::Narrators::SectionParser::MissingSectionsError,
      /missing sections cast_and_roles, interpersonal_dynamics, conversational_arc, data_quality, takeaways/
    )
  end

  it "treats a heading with an empty body as missing" do
    text = full_text.sub("Turns 7-9 are unmeasured.", "")

    expect { described_class.call(text) }.to raise_error(described_class::MissingSectionsError, /data_quality/)
  end

  it "is an analysis narrative error, so the analysis layer does not wrap it" do
    expect(described_class::MissingSectionsError.ancestors).to include(SFL::Analysis::NarrativeError)
  end
end
