module SFL::Core::Loaders::YamlDocumentAnalysisLoader
  include SFL::Core::Loaders::Source
  def each_unit
    data = YAML.load(file_content)
    unit = SFL::Core::Types::Unit.new
    unit.speaker = 'System'
    unit.text = data['description']
    unit.sent_at = Time.parse(data['timestamp'])
    yield unit
  end
end