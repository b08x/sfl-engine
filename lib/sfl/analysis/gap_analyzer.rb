# frozen_string_literal: true

module SFL
  module Analysis
    # Tests whether tenor spikes are more frequent in the turns that follow a
    # long pause.
    #
    # Input: Array<Hash> of conversations, each {turns: [{timestamp: Time,
    # spike: Boolean}, ...]}. Turns must be in chronological order. spike is
    # true when the turn is a tenor spike. The caller computes spikes with
    # TenorTracker#detect_significant_shifts (its turn_id values mark the spike
    # turns). Nothing is read from disk.
    #
    # Pauses: within each conversation, the gap between consecutive turns is
    # (timestamp[i] - timestamp[i-1]) in seconds. A gap is a long pause when
    # BOTH hold:
    #   - it is strictly greater than the conversation's 75th percentile of its
    #     own gaps, using linear interpolation between order statistics
    #     (rank = (n - 1) * 0.75 over the sorted gaps; NumPy/R type 7);
    #   - it is at least the floor (default 600 seconds).
    # A turn is "after a long pause" when the gap preceding it is a long pause.
    # The first turn of each conversation has no preceding gap and counts as
    # "other".
    #
    # Test: a two-sided Fisher exact test on
    #   [[after_spikes, after_nonspikes], [other_spikes, other_nonspikes]].
    # The exact hypergeometric computation runs when the table total is at most
    # 1000 and every expected cell (row total * column total / N) is at least 5.
    # Otherwise a permutation test runs. It shuffles the spike labels across
    # turns, with a fixed seed (default 42), for 10000 permutations by default.
    # It compares |rate_after - rate_other| and reports (hits + 1) / (N + 1).
    #
    # Output: {long_pause_threshold_seconds:, after_long_pause: {turns:, spikes:,
    # rate:}, other: {turns:, spikes:, rate:}, p_value:, method:, reason:}.
    # long_pause_threshold_seconds is the configured floor. The per-conversation
    # cutoff is max(percentile, floor). p_value and method are nil, with reason
    # set, when a group is empty. Otherwise reason is nil.
    class GapAnalyzer # rubocop:disable Metrics/ClassLength -- the exact hypergeometric helpers and the permutation test share one statistic; splitting them would scatter a single test across files outside the brief
      PERCENTILE = 75
      DEFAULT_FLOOR_SECONDS = 600
      DEFAULT_PERMUTATIONS = 10_000
      DEFAULT_SEED = 42
      EXACT_MAX_TOTAL = 1000
      MIN_EXPECTED_CELL = 5

      # Linear-interpolation percentile over a non-empty collection of numbers.
      def self.percentile(values, pct)
        sorted = values.sort
        rank = (sorted.size - 1) * pct / 100.0
        low = rank.floor
        sorted[low] + ((rank - low) * (sorted[rank.ceil] - sorted[low]))
      end

      # Two-sided Fisher exact p-value for [[a, b], [c, d]] with exact rational
      # hypergeometric probabilities. A table outcome counts when its
      # probability is at most the observed table's probability.
      def self.fisher_exact(table)
        (a, b), (c, d) = table
        total = a + b + c + d
        row_total = a + b
        col_total = a + c
        observed = hypergeometric(a, row_total, col_total, total)
        outcomes = (lower_bound(row_total, col_total, total)..upper_bound(row_total, col_total)).map do |cell|
          hypergeometric(cell, row_total, col_total, total)
        end
        outcomes.select { |probability| probability <= observed }.sum.to_f
      end

      def self.lower_bound(row_total, col_total, total)
        [0, row_total - (total - col_total)].max
      end

      def self.upper_bound(row_total, col_total)
        [row_total, col_total].min
      end

      # P(X = cell) for the hypergeometric distribution, as an exact Rational.
      def self.hypergeometric(cell, row_total, col_total, total)
        Rational(binomial(col_total, cell) * binomial(total - col_total, row_total - cell), binomial(total, row_total))
      end

      def self.binomial(total, choose)
        return 0 if choose.negative? || choose > total

        (1..choose).reduce(1) { |acc, step| acc * (total - choose + step) / step }
      end

      def initialize(conversations, floor_seconds: DEFAULT_FLOOR_SECONDS,
        permutations: DEFAULT_PERMUTATIONS, seed: DEFAULT_SEED
      )
        @conversations = conversations
        @floor_seconds = floor_seconds
        @permutations = permutations
        @seed = seed
      end

      def call
        flagged = @conversations.flat_map { |conversation| flag_turns(conversation) }
        after, other = flagged.partition(&:first)
        p_value, method, reason = test_outcome(flagged, after, other)

        {
          long_pause_threshold_seconds: @floor_seconds,
          after_long_pause: summary(after),
          other: summary(other),
          p_value:,
          method:,
          reason:,
        }
      end

      # Each turn becomes [after_long_pause, spike].
      private def flag_turns(conversation)
        turns = conversation[:turns]
        timestamps = turns.map { |turn| turn[:timestamp] }
        gaps = timestamps.each_cons(2).map { |earlier, later| later - earlier }
        flags = [false, *long_pause_flags(gaps)]

        turns.zip(flags).map { |turn, flag| [flag, turn[:spike]] }
      end

      private def long_pause_flags(gaps)
        return [] if gaps.empty?

        cutoff = self.class.percentile(gaps, PERCENTILE)
        gaps.map { |gap| gap > cutoff && gap >= @floor_seconds }
      end

      private def summary(group)
        spikes = group.count { |_flag, spike| spike }
        turns = group.size
        { turns:, spikes:, rate: turns.zero? ? nil : spikes.fdiv(turns) }
      end

      private def test_outcome(flagged, after, other)
        return unavailable("no long pause in any conversation") if after.empty?
        return unavailable("no turns outside long pauses") if other.empty?

        table = contingency(after, other)
        if exact?(table)
          [self.class.fisher_exact(table), "exact", nil]
        else
          [permutation_p_value(flagged, after), "permutation", nil]
        end
      end

      private def unavailable(reason)
        [nil, nil, reason]
      end

      private def contingency(after, other)
        after_spikes = after.count { |_flag, spike| spike }
        other_spikes = other.count { |_flag, spike| spike }
        [[after_spikes, after.size - after_spikes], [other_spikes, other.size - other_spikes]]
      end

      private def exact?(table)
        table.flatten.sum <= EXACT_MAX_TOTAL &&
          expected_cells(table).all? { |cell| cell >= MIN_EXPECTED_CELL }
      end

      private def expected_cells(table)
        rows = table.map(&:sum)
        cols = table.transpose.map(&:sum)
        total = rows.sum.to_f
        rows.product(cols).map { |row, col| row * col / total }
      end

      # Shuffles the spike labels across all turns and counts how often the
      # permuted rate gap is at least as large as the observed one. The
      # observed statistic is included in the count, so p is never 0.
      private def permutation_p_value(flagged, after)
        rng = Random.new(@seed)
        spikes = flagged.map { |_flag, spike| spike ? 1 : 0 }
        total_spikes = spikes.sum
        total = spikes.size
        after_size = after.size
        observed = rate_gap(after.count { |_flag, spike| spike }, total_spikes, total, after_size)

        gaps = Array.new(@permutations) do
          permuted = spikes.shuffle(random: rng)
          rate_gap(permuted.first(after_size).sum, total_spikes, total, after_size)
        end
        hits = gaps.count { |gap| gap >= observed - 1e-12 }

        (hits + 1).fdiv(@permutations + 1)
      end

      private def rate_gap(after_spikes, total_spikes, total, after_size)
        after_rate = after_spikes.fdiv(after_size)
        other_rate = (total_spikes - after_spikes).fdiv(total - after_size)
        (after_rate - other_rate).abs
      end
    end
  end
end
