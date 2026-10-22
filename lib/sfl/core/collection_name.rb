# frozen_string_literal: true

module SFL
  module Core
    # The one rule for collection names: surrounding whitespace is trimmed,
    # case is kept, and an empty name is rejected. Uniqueness ignoring case
    # is enforced by the store (a unique index on lower(name)).
    module CollectionName
      # Raised for an empty or whitespace-only name.
      class Error < SFL::Error; end

      # @param name [String, nil]
      # @return [String] the trimmed name
      # @raise [Error] when the trimmed name is empty
      module_function def normalize(name)
        trimmed = name.to_s.strip
        raise Error, "collection name must not be empty" if trimmed.empty?

        trimmed
      end

      # Default collection for an input path: the basename of its expanded path.
      # @param input [String]
      # @return [String]
      module_function def default_for(input) = File.basename(File.expand_path(input.to_s))
    end
  end
end
