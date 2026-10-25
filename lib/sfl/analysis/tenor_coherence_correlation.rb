# frozen_string_literal: true

module SFL
  module Analysis
    # Spearman rank correlation between a conversation's average tenor and its
    # semantic coherence score, with a two-sided p-value.
    #
    # Input: Array<Hash> of rows, each with :avg_tenor (Float or nil) and
    # :semantic_coherence_score (Float or nil). A row is usable only when both
    # values are non-nil. Nothing is read from disk; the caller loads the data.
    #
    # Output: {coefficient:, p_value:, n:}, where n is the count of usable rows.
    # coefficient and p_value are nil when n < 3, or when either variable is
    # constant among the usable rows (no rank spread, so no correlation).
    #
    # Ties get average ranks. The coefficient is the Pearson correlation of the
    # average ranks, which is the tie-corrected Spearman coefficient. The
    # p-value uses t = r * sqrt((n - 2) / (1 - r^2)) with n - 2 degrees of
    # freedom, two-sided, from the Student t CDF. That CDF is the regularized
    # incomplete beta I_x(df/2, 1/2) with x = df / (df + t^2), evaluated by a
    # Lentz continued fraction (Numerical Recipes, betacf).
    class TenorCoherenceCorrelation
      MIN_PAIRS = 3
      MAX_ITERATIONS = 300
      EPSILON = 3.0e-14
      TINY = 1.0e-300

      def initialize(rows)
        @rows = rows
      end

      def call
        pairs = usable_pairs
        n = pairs.size
        return { coefficient: nil, p_value: nil, n: } if n < MIN_PAIRS

        r = spearman(pairs.map(&:first), pairs.map(&:last))
        { coefficient: r, p_value: r && p_value_for(r, n), n: }
      end

      private def usable_pairs
        @rows
          .map { |row| [row[:avg_tenor], row[:semantic_coherence_score]] }
          .reject { |tenor, coherence| tenor.nil? || coherence.nil? }
      end

      private def spearman(left, right)
        pearson(average_ranks(left), average_ranks(right))
      end

      # Ranks start at 1; each tie group takes the mean of the ranks it spans.
      private def average_ranks(values)
        order = values.each_index.sort_by { |index| values[index] }
        ranks = Array.new(values.size)
        order.chunk_while { |first, second| values[first] == values[second] }.reduce(0) do |offset, group|
          group.each { |index| ranks[index] = offset + ((group.size + 1) / 2.0) }
          offset + group.size
        end
        ranks
      end

      private def pearson(left, right)
        dev_left = centered(left)
        dev_right = centered(right)
        sum_left = dot(dev_left, dev_left)
        sum_right = dot(dev_right, dev_right)
        return nil if sum_left.zero? || sum_right.zero?

        (dot(dev_left, dev_right) / Math.sqrt(sum_left * sum_right)).clamp(-1.0, 1.0).round(12)
      end

      private def centered(values)
        mean = values.sum.fdiv(values.size)
        values.map { |value| value - mean }
      end

      private def dot(left, right)
        left.zip(right).sum { |x, y| x * y }
      end

      # Two-sided p-value of t = r * sqrt((n - 2) / (1 - r^2)) with n - 2 df.
      private def p_value_for(coefficient, count)
        return 0.0 if coefficient.abs >= 1.0

        df = count - 2
        t_squared = (coefficient * coefficient * df) / (1.0 - (coefficient * coefficient))
        regularized_beta(df / (df + t_squared), df / 2.0, 0.5)
      end

      # I_x(alpha, beta), evaluated where the continued fraction converges.
      private def regularized_beta(point, alpha, beta)
        return 0.0 if point <= 0.0
        return 1.0 if point >= 1.0

        if point < (alpha + 1.0) / (alpha + beta + 2.0)
          beta_front(point, alpha, beta) * beta_continued_fraction(point, alpha, beta) / alpha
        else
          1.0 - (beta_front(1.0 - point, beta, alpha) * beta_continued_fraction(1.0 - point, beta, alpha) / beta)
        end
      end

      private def beta_front(point, alpha, beta)
        log_value = Math.lgamma(alpha + beta).first - Math.lgamma(alpha).first - Math.lgamma(beta).first +
          (alpha * Math.log(point)) + (beta * Math.log(1.0 - point))
        Math.exp(log_value)
      end

      private def beta_continued_fraction(point, alpha, beta)
        c = 1.0
        d = 1.0 / guard(1.0 - ((alpha + beta) * point / (alpha + 1.0)))
        h = d
        1.upto(MAX_ITERATIONS) do |step|
          c, d, factor = lentz_step(even_term(step, point, alpha, beta), c, d)
          h *= factor
          c, d, factor = lentz_step(odd_term(step, point, alpha, beta), c, d)
          h *= factor
          return h if (factor - 1.0).abs < EPSILON
        end
        h
      end

      private def lentz_step(term, prev_c, prev_d)
        next_d = 1.0 / guard(1.0 + (term * prev_d))
        next_c = guard(1.0 + (term / prev_c))
        [next_c, next_d, next_d * next_c]
      end

      private def even_term(step, point, alpha, beta)
        twice = 2 * step
        (step * (beta - step) * point) / ((alpha - 1.0 + twice) * (alpha + twice))
      end

      private def odd_term(step, point, alpha, beta)
        twice = 2 * step
        (-(alpha + step) * (alpha + beta + step) * point) / ((alpha + twice) * (alpha + 1.0 + twice))
      end

      private def guard(value)
        (value.abs < TINY) ? TINY : value
      end
    end
  end
end
