# frozen_string_literal: true

module SFL
  module Analysis
    # Raised by TopicModeler#fit when two sidecar attempts both leave topic
    # coverage at or below the gate. Nothing is stored when it is raised.
    class TopicCoverageError < Error; end
  end
end
