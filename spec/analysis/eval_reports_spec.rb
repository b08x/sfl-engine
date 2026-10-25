# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe SFL::Analysis::EvalReports do
  let(:sources) { ["output/eval/nd-11/conversation_analysis.json", "output/eval/nd-12/conversation_analysis.json"] }

  def render(name, result)
    described_class.render(name, result, sources:)
  end

  describe ".render with :tenor_coherence" do
    let(:result) { { coefficient: 0.4123456, p_value: 0.0123, n: 17 } }

    it "returns markdown and JSON text" do
      rendered = render(:tenor_coherence, result)

      expect(rendered.keys).to contain_exactly(:markdown, :json)
      expect(rendered[:markdown]).to be_a(String)
      expect(rendered[:json]).to be_a(String)
    end

    it "states n, the coefficient, the p-value and each source path in the markdown" do
      markdown = render(:tenor_coherence, result)[:markdown]

      expect(markdown).to include("| n (usable turns) | 17 |")
      expect(markdown).to include("| Coefficient (rho) | 0.412 |")
      expect(markdown).to include("| p-value | 0.0123 |")
      sources.each { |path| expect(markdown).to include("- #{path}") }
    end

    it "parses back to the same values in the JSON" do
      json = JSON.parse(render(:tenor_coherence, result)[:json])

      expect(json).to eq(
        "report" => "tenor_coherence",
        "sources" => sources,
        "result" => { "coefficient" => 0.4123456, "p_value" => 0.0123, "n" => 17 }
      )
    end

    it "says the coefficient is not computed and states n when the coefficient is nil" do
      nil_result = { coefficient: nil, p_value: nil, n: 2 }
      rendered = render(:tenor_coherence, nil_result)

      expect(rendered[:markdown]).to include("| n (usable turns) | 2 |")
      expect(rendered[:markdown]).to include("| Coefficient (rho) | not computed |")
      expect(rendered[:markdown]).to include("| p-value | not computed |")
      expect(rendered[:markdown]).to include("n = 2")
      expect(JSON.parse(rendered[:json])["result"]).to eq("coefficient" => nil, "p_value" => nil, "n" => 2)
    end
  end

  describe ".render with :process_mix" do
    let(:result) do
      {
        baseline: { "material" => 0.5, "mental" => 0.25, "relational" => 0.25 },
        per_speaker: {
          "Alice" => {
            distribution: { "material" => 1.0, "mental" => 0.0, "relational" => 0.0 },
            deviation: { "material" => 0.5, "mental" => -0.25, "relational" => -0.25 },
            total_deviation: 0.5,
          },
        },
      }
    end

    it "renders the baseline and each speaker's deviations" do
      markdown = render(:process_mix, result)[:markdown]

      expect(markdown).to include("| material | 0.500 |")
      expect(markdown).to include("## Alice (total deviation 0.500)")
      expect(markdown).to include("| material | 1.000 | 0.500 |")
      expect(markdown).to include("| mental | 0.000 | -0.250 |")
    end

    it "parses back to the same values in the JSON" do
      json = JSON.parse(render(:process_mix, result)[:json])

      expect(json["report"]).to eq("process_mix")
      expect(json["result"]).to eq(JSON.parse(result.to_json))
    end

    it "states that there is no baseline when no trusted clauses exist" do
      empty = { baseline: {}, per_speaker: {} }
      rendered = render(:process_mix, empty)

      expect(rendered[:markdown]).to include("No trusted clauses")
      expect(JSON.parse(rendered[:json])["result"]).to eq("baseline" => {}, "per_speaker" => {})
    end
  end

  describe ".render with :gap_analysis" do
    let(:result) do
      {
        long_pause_threshold_seconds: 600,
        after_long_pause: { turns: 6, spikes: 3, rate: 0.5 },
        other: { turns: 20, spikes: 2, rate: 0.1 },
        p_value: 0.0456,
        method: "exact",
        reason: nil,
      }
    end

    it "states the threshold, counts, rates, p-value and method" do
      markdown = render(:gap_analysis, result)[:markdown]

      expect(markdown).to include("| Threshold (floor, seconds) | 600 |")
      expect(markdown).to include("| After long pause | 6 | 3 | 0.500 |")
      expect(markdown).to include("| Other | 20 | 2 | 0.100 |")
      expect(markdown).to include("| p-value | 0.0456 |")
      expect(markdown).to include("| Method | exact |")
    end

    it "parses back to the same values in the JSON" do
      json = JSON.parse(render(:gap_analysis, result)[:json])

      expect(json["report"]).to eq("gap_analysis")
      expect(json["result"]).to eq(JSON.parse(result.to_json))
    end

    it "states the reason and marks the p-value and method not computed when a group is empty" do
      unavailable = result.merge(p_value: nil, method: nil, reason: "no long pause in any conversation")
      rendered = render(:gap_analysis, unavailable)

      expect(rendered[:markdown]).to include("| p-value | not computed |")
      expect(rendered[:markdown]).to include("| Method | not computed |")
      expect(rendered[:markdown]).to include("no long pause in any conversation")
      expect(JSON.parse(rendered[:json])["result"]).to include("p_value" => nil, "method" => nil)
    end
  end

  describe ".render with an unknown name" do
    it "raises ArgumentError" do
      expect { render(:unknown, {}) }.to raise_error(ArgumentError, /unknown eval report/)
    end
  end
end
