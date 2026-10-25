# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Analysis::TenorCoherenceCorrelation do
  def rows_from(tenors, coherences)
    tenors.zip(coherences).map { |t, c| { avg_tenor: t, semantic_coherence_score: c } }
  end

  def call(rows)
    described_class.new(rows).call
  end

  # Two-sided p for a t statistic with df = 3, closed form:
  # P(|T| > t) = 1 - (2/pi) * ((t / sqrt(3)) / (1 + t^2 / 3) + atan(t / sqrt(3)))
  def closed_form_p_df3(stat)
    u = stat / Math.sqrt(3.0)
    1.0 - ((2.0 / Math::PI) * ((u / (1.0 + ((stat * stat) / 3.0))) + Math.atan(u)))
  end

  describe "#call" do
    it "returns a coefficient of 1.0 for a perfectly monotone increasing sequence" do
      result = call(rows_from([1.0, 2.0, 3.0, 4.0, 5.0], [2.0, 4.0, 6.0, 8.0, 10.0]))

      expect(result[:coefficient]).to be_within(1e-12).of(1.0)
      expect(result[:n]).to eq(5)
      expect(result[:p_value]).to eq(0.0)
    end

    it "returns a coefficient of -1.0 for a perfectly reversed sequence" do
      result = call(rows_from([1.0, 2.0, 3.0, 4.0, 5.0], [9.0, 7.0, 5.0, 3.0, 1.0]))

      expect(result[:coefficient]).to be_within(1e-12).of(-1.0)
      expect(result[:p_value]).to eq(0.0)
    end

    # Hand computation. x = [1, 2, 2, 3, 4] has average ranks [1, 2.5, 2.5, 4, 5].
    # y = [1, 3, 2, 5, 4] has ranks [1, 3, 2, 5, 4]. Both rank means are 3.
    # Deviations dx = [-2, -0.5, -0.5, 1, 2], dy = [-2, 0, -1, 2, 1].
    # sxy = 8.5, sxx = 9.5, syy = 10, so r = 8.5 / sqrt(95).
    # n = 5, df = 3, t = r * sqrt(3 / (1 - r^2)) = 3.0867, two-sided p = 0.0541.
    it "matches a hand-computed Spearman value for a fixture with ties" do
      result = call(rows_from([1.0, 2.0, 2.0, 3.0, 4.0], [1.0, 3.0, 2.0, 5.0, 4.0]))

      r = 8.5 / Math.sqrt(95.0)
      t = r * Math.sqrt(3.0 / (1.0 - (r * r)))

      expect(result[:coefficient]).to be_within(1e-9).of(r)
      expect(result[:p_value]).to be_within(1e-6).of(closed_form_p_df3(t))
      expect(result[:p_value]).to be_within(1e-3).of(0.0541)
      expect(result[:n]).to eq(5)
    end

    it "excludes rows where either value is nil and counts only the usable pairs" do
      tenors = [1.0, nil, 2.0, 2.0, 3.0, 4.0, nil]
      coherences = [1.0, 0.5, 3.0, 2.0, 5.0, 4.0, 9.0]

      result = call(rows_from(tenors, coherences))

      expect(result[:n]).to eq(5)
      expect(result[:coefficient]).to be_within(1e-9).of(8.5 / Math.sqrt(95.0))
    end

    it "reports n of zero when every row has a nil" do
      result = call(rows_from([nil, nil], [1.0, nil]))

      expect(result).to eq({ coefficient: nil, p_value: nil, n: 0 })
    end

    it "returns a nil coefficient and p-value when n is below 3" do
      result = call(rows_from([1.0, 2.0], [3.0, 4.0]))

      expect(result).to eq({ coefficient: nil, p_value: nil, n: 2 })
    end

    it "returns a nil coefficient when one variable is constant" do
      result = call(rows_from([1.0, 2.0, 3.0], [5.0, 5.0, 5.0]))

      expect(result[:coefficient]).to be_nil
      expect(result[:p_value]).to be_nil
      expect(result[:n]).to eq(3)
    end

    it "does not hardcode n" do
      rows = rows_from([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0], [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0])

      expect(call(rows)[:n]).to eq(7)
    end
  end

  describe "t distribution p-value (regularized incomplete beta)" do
    let(:correlation) { described_class.new([]) }

    # df = 1 is the Cauchy distribution: P(|T| > t) = 1 - (2/pi) atan(t).
    # With n = 3, t^2 = r^2 / (1 - r^2); r = 1/sqrt(2) gives t = 1, so p = 0.5.
    it "matches the Cauchy closed form for one degree of freedom" do
      r = 1.0 / Math.sqrt(2.0)

      expect(correlation.__send__(:p_value_for, r, 3)).to be_within(1e-10).of(0.5)
    end

    # df = 2: P(|T| > t) = 1 - t / sqrt(t^2 + 2). With n = 4, r = 1/sqrt(3) gives t = 1.
    it "matches the closed form for two degrees of freedom" do
      r = 1.0 / Math.sqrt(3.0)

      expect(correlation.__send__(:p_value_for, r, 4)).to be_within(1e-10).of(1.0 - (1.0 / Math.sqrt(3.0)))
    end

    it "matches the closed form for three degrees of freedom" do
      r = 0.6

      t = r * Math.sqrt(3.0 / (1.0 - (r * r)))
      expect(correlation.__send__(:p_value_for, r, 5)).to be_within(1e-10).of(closed_form_p_df3(t))
    end
  end
end
