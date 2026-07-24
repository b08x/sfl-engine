# frozen_string_literal: true

require "spec_helper"

# Guards against Zeitwerk::NameError going undetected: a file/constant-name
# mismatch anywhere under lib/sfl/ only actually raises when that file is
# loaded, whether via a normal reference or an explicit eager_load. Nothing
# else in the suite calls eager_load, so a mismatched file with no current
# callers (like SFL::Core::Types::TRUSTED_ANNOTATION_SOURCES, until this
# spec was added) can sit broken and undetected indefinitely.
RSpec.describe "Zeitwerk configuration" do # rubocop:disable RSpec/DescribeClass -- no single class under test, this exercises the whole loader
  it "eager-loads the entire lib/sfl/ tree without a Zeitwerk::NameError" do
    expect { SFL.loader.eager_load }.not_to raise_error
  end
end
