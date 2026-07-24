# frozen_string_literal: true

module SFL
  module Analysis
    # Raised by NarrativeGenerator#generate when the injected narrator
    # fails outright, or succeeds but hands back a Hash that
    # Types::NarrativeReport rejects (missing/malformed SECTION_KEYS).
    class NarrativeError < Error; end
  end
end
