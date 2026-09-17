# frozen_string_literal: true

# Spec helper: builds a FileRef from a path, the same way production code
# does via Core::Refs::FileRefBuilder. Specs that construct loaders
# should call `file_ref(path)` instead of passing a raw string path.
module FileRefHelper
  def file_ref(path, source_id: path.to_s)
    SFL::Core::Refs::FileRefBuilder.call(path, source_id:)
  end
end

RSpec.configure do |config|
  config.include FileRefHelper
end
