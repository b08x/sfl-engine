# frozen_string_literal: true

# Minimal Analysis::Source duck for spec/analysis/engine_spec.rb —
# #units/#review_entry/#extra_metadata, the same three methods
# ConversationSource/DocumentationSource implement. Lives under spec/support
# (not inline in engine_spec.rb) so RSpec's example-group-scoped cops
# (RSpec/InstanceVariable, Lint/ConstantDefinitionInBlock) don't fire on what
# is really a plain support class, not an example.
class FakeAnalysisSource
  def initialize(units, review_entries: {}, extra: {})
    @units = units
    @review_entries = review_entries
    @extra = extra
  end

  attr_reader :units

  def review_entry(unit:, clauses:) # rubocop:disable Lint/UnusedMethodArgument -- shared Source#review_entry contract
    @review_entries[unit.document_id]
  end

  def extra_metadata(_turns) = @extra
end
