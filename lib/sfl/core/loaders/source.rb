# frozen_string_literal: true

module SFL
  module Core
    module Loaders
      # Alias for Core::Ports::Loader (SFL-ING-01). All 13 existing
      # implementers `include Source` and continue to work unchanged;
      # new code should `include Core::Ports::Loader` directly.
      module Source
        include Core::Ports::Loader
      end
    end
  end
end
