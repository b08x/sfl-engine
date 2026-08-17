Pattern 3: Tool Integration (ReAct/CodeAct)
Use Informers pipelines as tools in agentic workflows:
class InformersTool < DSPy::Tools::Tool
  description "Run ML inference using Informers pipelines"
  
  param :task, String, desc: "Pipeline task (text-classification, embeddings, etc.)"
  param :input, String, desc: "Input text or data"
  param :model, String, desc: "Model identifier", optional: true

  def call(task:, input:, model: nil)
    pipeline = Informers::pipeline(
      task: task,
      model: default_model_for(task)
    )
    
    result = pipeline.call(input)
    result.to_json
  end

  private

  def default_model_for(task)
    case task
    when "text-classification"
      "Xenova/distilbert-base-uncased-finetuned-sst-2-english"
    when "feature-extraction"
      "sentence-transformers/all-MiniLM-L6-v2"
    when "text-generation"
      "Xenova/gpt2"
    else
      raise "Unknown task: #{task}"
    end
  end
end

# Use in ReAct agent
agent = DSPy::ReAct.new(
  signature: ResearchSignature,
  tools: [InformersTool.new, OtherTools...]
)
