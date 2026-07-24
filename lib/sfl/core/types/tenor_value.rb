# frozen_string_literal: true

module SFL
  module Core
    module Types
      TenorValue = Types::Float.constrained(gteq: 0.0, lteq: 1.0)
    end
  end
end
