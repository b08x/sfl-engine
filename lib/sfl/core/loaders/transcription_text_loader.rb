module SFL::Core::Loaders::TranscriptionTextLoader
  include SFL::Core::Loaders::Source
  
  def initialize(file_path)
    @file_path = file_path
  end
  
  def each_unit
    File.foreach(@file_path) do |line|
      yield SFL::Core::Types::Unit.new(speaker: 'Unknown', text: line.strip, sent_at: nil)
    end
  end
end