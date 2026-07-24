# frozen_string_literal: true

module SFL
  module Analysis
    # Raised when Analysis::Engine can't proceed — currently only when a
    # Pipeline#compile call itself returns Failure (a Pass 1 failure the
    # pipeline already logged; Engine has nothing useful to add beyond
    # surfacing it with the document_id that failed).
    class Error < SFL::Error; end
  end
end
