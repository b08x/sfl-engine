# frozen_string_literal: true

# Step stubs for features/bertopic_sidecar.feature.
# Each stub raises NotImplementedError with its step text. No behaviour is implemented here.

Given("the sfl-engine checkout with the BERTopic sidecar change applied") do
  raise NotImplementedError, "the sfl-engine checkout with the BERTopic sidecar change applied"
end

Given(%r{\Athe\ sidecar\ is\ started\ from\ sidecar/spacy_sidecar\.py\ with\ a\ model\ argument\z}) do
  raise NotImplementedError, "the sidecar is started from sidecar/spacy_sidecar.py with a model argument"
end

Given("SFL::Boot is the only code that reads the embedding environment variables") do
  raise NotImplementedError, "SFL::Boot is the only code that reads the embedding environment variables"
end

When("the sidecar starts") do
  raise NotImplementedError, "the sidecar starts"
end

Then(/\Aits\ first\ stdout\ line\ is\ \{"type":\ "ready",\ "model":\ "<name>"\}\z/) do
  raise NotImplementedError, "its first stdout line is {\"type\": \"ready\", \"model\": \"<name>\"}"
end

Then("it reads no request before writing that line") do
  raise NotImplementedError, "it reads no request before writing that line"
end

When("a bertopic request with id {string}, {int} texts, {int} embedding vectors of {int} floats, nr_topics {int}, min_topic_size {int} and seed {int} is written to stdin") do
  raise NotImplementedError, "a bertopic request with id \"req-1\", 4 texts, 4 embedding vectors of 3 floats, nr_topics 2, min_topic_size 2 and seed 42 is written to stdin"
end

Then("exactly one response line follows with id {string}") do
  raise NotImplementedError, "exactly one response line follows with id \"req-1\""
end

Then("the response has {string} as an array of {int} integers") do
  raise NotImplementedError, "the response has \"topics\" as an array of 4 integers"
end

Then("the response has {string} as an object whose values are arrays of strings") do
  raise NotImplementedError, "the response has \"topic_words\" as an object whose values are arrays of strings"
end

Then("the response has {string} equal to -1") do
  raise NotImplementedError, "the response has \"outlier_topic\" equal to -1"
end

Then("the sidecar has started no second process") do
  raise NotImplementedError, "the sidecar has started no second process"
end

Given("outbound network access from the sidecar process is blocked") do
  raise NotImplementedError, "outbound network access from the sidecar process is blocked"
end

When("a bertopic request with {int} texts and their vectors is answered") do
  raise NotImplementedError, "a bertopic request with 6 texts and their vectors is answered"
end

Then("the response is written with the standard shape") do
  raise NotImplementedError, "the response is written with the standard shape"
end

Then("the sidecar loads no embedding model from disk or from the network") do
  raise NotImplementedError, "the sidecar loads no embedding model from disk or from the network"
end

When("a bertopic request has {string}: null") do
  raise NotImplementedError, "a bertopic request has \"nr_topics\": null"
end

Then("the sidecar answers it with the standard response shape") do
  raise NotImplementedError, "the sidecar answers it with the standard response shape"
end

Then("it does not return an error for the null value") do
  raise NotImplementedError, "it does not return an error for the null value"
end

When("a bertopic request with id {string} omits {string}") do
  raise NotImplementedError, "a bertopic request with id \"req-2\" omits \"min_topic_size\""
end

Then("one error line is written with id {string} and an {string} message") do
  raise NotImplementedError, "one error line is written with id \"req-2\" and an \"error\" message"
end

When("a valid bertopic request with id {string} is written") do
  raise NotImplementedError, "a valid bertopic request with id \"req-3\" is written"
end

Then("the response with id {string} is written") do
  raise NotImplementedError, "the response with id \"req-3\" is written"
end

Given("SFL_TASK_EMBEDDING_PROVIDER is {string}") do
  raise NotImplementedError, "SFL_TASK_EMBEDDING_PROVIDER is \"ollama\""
end

Given("SFL_TASK_EMBEDDING_MODEL is {string}") do
  raise NotImplementedError, "SFL_TASK_EMBEDDING_MODEL is \"embeddinggemma-2:440m\""
end

When("SFL::Boot resolves the embedding configuration") do
  raise NotImplementedError, "SFL::Boot resolves the embedding configuration"
end

Then("the provider is {string}") do
  raise NotImplementedError, "the provider is \"ollama\""
end

Then("the model is {string}") do
  raise NotImplementedError, "the model is \"embeddinggemma-2:440m\""
end

Given("SFL_TASK_EMBEDDING_PROVIDER and SFL_TASK_EMBEDDING_MODEL are unset") do
  raise NotImplementedError, "SFL_TASK_EMBEDDING_PROVIDER and SFL_TASK_EMBEDDING_MODEL are unset"
end

Given("SFL::Boot is loaded while SFL_TASK_EMBEDDING_MODEL is unset") do
  raise NotImplementedError, "SFL::Boot is loaded while SFL_TASK_EMBEDDING_MODEL is unset"
end

When("SFL_TASK_EMBEDDING_MODEL is set to {string} and the configuration is resolved") do
  raise NotImplementedError, "SFL_TASK_EMBEDDING_MODEL is set to \"embeddinggemma-2:440m\" and the configuration is resolved"
end

Then("the resolved model is {string}") do
  raise NotImplementedError, "the resolved model is \"embeddinggemma-2:440m\""
end

When("the consolidation spec is run") do
  raise NotImplementedError, "the consolidation spec is run"
end

Then("it passes") do
  raise NotImplementedError, "it passes"
end

Then(%r{\Ano\ ENV\ read\ of\ SFL_TASK_EMBEDDING_PROVIDER\ or\ SFL_TASK_EMBEDDING_MODEL\ exists\ under\ lib/,\ exe/\ or\ rakelib/\ outside\ lib/sfl/boot\*\z}) do
  raise NotImplementedError, "no ENV read of SFL_TASK_EMBEDDING_PROVIDER or SFL_TASK_EMBEDDING_MODEL exists under lib/, exe/ or rakelib/ outside lib/sfl/boot*"
end

Then(".env.example names SFL_TASK_EMBEDDING_PROVIDER and SFL_TASK_EMBEDDING_MODEL, active or commented") do
  raise NotImplementedError, ".env.example names SFL_TASK_EMBEDDING_PROVIDER and SFL_TASK_EMBEDDING_MODEL, active or commented"
end

Then("SFL::Analysis::TopicModeler responds to fit, turn_distributions, detect_topic_shifts, calculate_coherence and conversation_baseline") do
  raise NotImplementedError, "SFL::Analysis::TopicModeler responds to fit, turn_distributions, detect_topic_shifts, calculate_coherence and conversation_baseline"
end

Then("the engine calls those methods with the same arguments as before the change") do
  raise NotImplementedError, "the engine calls those methods with the same arguments as before the change"
end

When("TopicModeler is built with k nil and fit is called") do
  raise NotImplementedError, "TopicModeler is built with k nil and fit is called"
end

Then("the bertopic request carries {string}: null") do
  raise NotImplementedError, "the bertopic request carries \"nr_topics\": null"
end

When("TopicModeler is built with k {int} and fit is called") do
  raise NotImplementedError, "TopicModeler is built with k 5 and fit is called"
end

Then("the bertopic request carries {string}: {int}") do
  raise NotImplementedError, "the bertopic request carries \"nr_topics\": 5"
end

Then("Gemfile and Gemfile.lock name no LDA or HDP topic gem") do
  raise NotImplementedError, "Gemfile and Gemfile.lock name no LDA or HDP topic gem"
end

Then("the TopicModeler spec passes without that gem installed") do
  raise NotImplementedError, "the TopicModeler spec passes without that gem installed"
end

Then("calling save on a TopicModeler raises NoMethodError") do
  raise NotImplementedError, "calling save on a TopicModeler raises NoMethodError"
end

Then("calling load_model on a TopicModeler raises NoMethodError") do
  raise NotImplementedError, "calling load_model on a TopicModeler raises NoMethodError"
end

Given("a section by speaker {string} whose text is {string}") do
  raise NotImplementedError, "a section by speaker \"Alice\" whose text is \"Alice: we should ship the parser on Friday\""
end

When("the topic input cleaner runs on the section") do
  raise NotImplementedError, "the topic input cleaner runs on the section"
end

Then("the topic input for that section is {string}") do
  raise NotImplementedError, "the topic input for that section is \"we should ship the parser on Friday\""
end

Given(/\Aa\ section\ containing\ a\ system\ preamble\ "You\ are\ a\ helpful\ assistant\.",
  \ a\ tool\ trace\ "<tool_call\ name=\\"search\\">",\ and\ a\ repeated\ header\ "\#\#\ Transcript"\z/x) do
  raise NotImplementedError,
    "a section containing a system preamble \"You are a helpful assistant.\", a tool trace \"<tool_call name=\\\"search\\\">\", and a repeated header \"## Transcript\""
end

Then("none of the three boilerplate fragments appears in the topic input") do
  raise NotImplementedError, "none of the three boilerplate fragments appears in the topic input"
end

Then("the content words of the section remain in the topic input") do
  raise NotImplementedError, "the content words of the section remain in the topic input"
end

Given("a document whose sections include speaker names and boilerplate") do
  raise NotImplementedError, "a document whose sections include speaker names and boilerplate"
end

When("Pass {int} runs and a topic model run is then performed on the document") do
  raise NotImplementedError, "Pass 1 runs and a topic model run is then performed on the document"
end

Then("each stored section text equals the source section text byte for byte") do
  raise NotImplementedError, "each stored section text equals the source section text byte for byte"
end

Then("the clause rows and Pass {int} output are identical to a run without the topic model run") do
  raise NotImplementedError, "the clause rows and Pass 1 output are identical to a run without the topic model run"
end

Given("{int} sections of which {int} become empty after cleaning") do
  raise NotImplementedError, "5 sections of which 2 become empty after cleaning"
end

When("the topic input cleaner runs") do
  raise NotImplementedError, "the topic input cleaner runs"
end

Then("it returns {int} entries in the input order, each carrying its section_id") do
  raise NotImplementedError, "it returns 5 entries in the input order, each carrying its section_id"
end

Then("the {int} emptied sections are kept as empty strings and are not dropped") do
  raise NotImplementedError, "the 2 emptied sections are kept as empty strings and are not dropped"
end

Given(/\A10\ sections\ of\ which\ the\ sidecar\ assigns\ a\ non-outlier\ topic\ to\ 4\z/) do
  raise NotImplementedError, "10 sections of which the sidecar assigns a non-outlier topic to 4"
end

When("TopicModeler fits the document") do
  raise NotImplementedError, "TopicModeler fits the document"
end

Then("exactly one bertopic request is sent") do
  raise NotImplementedError, "exactly one bertopic request is sent"
end

Then("the result reports coverage {float}") do
  raise NotImplementedError, "the result reports coverage 0.4"
end

Then("the result is stored once") do
  raise NotImplementedError, "the result is stored once"
end

Given(/\A10\ sections\ of\ which\ the\ sidecar\ assigns\ a\ non-outlier\ topic\ to\ 3\z/) do
  raise NotImplementedError, "10 sections of which the sidecar assigns a non-outlier topic to 3"
end

Then("a second bertopic request is sent") do
  raise NotImplementedError, "a second bertopic request is sent"
end

Given(/\Athe\ first\ attempt\ used\ nr_topics\ 8\ and\ min_topic_size\ 10\ and\ reached\ coverage\ 0\.2\z/) do
  raise NotImplementedError, "the first attempt used nr_topics 8 and min_topic_size 10 and reached coverage 0.2"
end

When("the retry is sent") do
  raise NotImplementedError, "the retry is sent"
end

Then("the retry's nr_topics is less than {int}") do
  raise NotImplementedError, "the retry's nr_topics is less than 8"
end

Then("the retry's min_topic_size is less than {int}") do
  raise NotImplementedError, "the retry's min_topic_size is less than 10"
end

Then("the retry reached coverage {float}") do
  raise NotImplementedError, "the retry reached coverage 0.5"
end

Then("the result reports coverage {float} and is stored once") do
  raise NotImplementedError, "the result reports coverage 0.5 and is stored once"
end

Then("exactly two bertopic requests were sent") do
  raise NotImplementedError, "exactly two bertopic requests were sent"
end

Given("the first attempt used nr_topics null and min_topic_size {int} and reached coverage {float}") do
  raise NotImplementedError, "the first attempt used nr_topics null and min_topic_size 10 and reached coverage 0.1"
end

Then("the retry's nr_topics is null") do
  raise NotImplementedError, "the retry's nr_topics is null"
end

Given(/\Athe\ first\ attempt\ used\ nr_topics\ 8\ and\ min_topic_size\ 10\ and\ reached\ coverage\ 0\.12\z/) do
  raise NotImplementedError, "the first attempt used nr_topics 8 and min_topic_size 10 and reached coverage 0.12"
end

Given("the retry used nr_topics {int} and min_topic_size {int} and reached coverage {float}") do
  raise NotImplementedError, "the retry used nr_topics 4 and min_topic_size 5 and reached coverage 0.18"
end

Then("a coverage error under SFL::Analysis::Error is raised") do
  raise NotImplementedError, "a coverage error under SFL::Analysis::Error is raised"
end

Then(/\Aits\ message\ names\ attempt\ 1\ with\ nr_topics\ 8,\ min_topic_size\ 10\ and\ coverage\ 0\.12\z/) do
  raise NotImplementedError, "its message names attempt 1 with nr_topics 8, min_topic_size 10 and coverage 0.12"
end

Then(/\Aits\ message\ names\ attempt\ 2\ with\ nr_topics\ 4,\ min_topic_size\ 5\ and\ coverage\ 0\.18\z/) do
  raise NotImplementedError, "its message names attempt 2 with nr_topics 4, min_topic_size 5 and coverage 0.18"
end

Then("no topic_models row is written for the run") do
  raise NotImplementedError, "no topic_models row is written for the run"
end

Then("no further bertopic request is sent after the retry") do
  raise NotImplementedError, "no further bertopic request is sent after the retry"
end

Given("a fit that passes the coverage gate for document key {string}") do
  raise NotImplementedError, "a fit that passes the coverage gate for document key \"transcript-42\""
end

When("the fit is stored") do
  raise NotImplementedError, "the fit is stored"
end

Then("one topic_models row exists with document key {string}") do
  raise NotImplementedError, "one topic_models row exists with document key \"transcript-42\""
end

Then("the row holds topics and topic_words as JSONB") do
  raise NotImplementedError, "the row holds topics and topic_words as JSONB"
end

Then("the row holds coverage, run id, created_at and updated_at") do
  raise NotImplementedError, "the row holds coverage, run id, created_at and updated_at"
end

Given("a stored fit with topics, topic_words and coverage") do
  raise NotImplementedError, "a stored fit with topics, topic_words and coverage"
end

When("the fit is read back through the store layer") do
  raise NotImplementedError, "the fit is read back through the store layer"
end

Then("the topics, topic_words and coverage equal the stored values") do
  raise NotImplementedError, "the topics, topic_words and coverage equal the stored values"
end

Given("the Ollama server lists {string}") do
  raise NotImplementedError, "the Ollama server lists \"embeddinggemma-2:440m\""
end

When("the embedding probe runs before a topic fit") do
  raise NotImplementedError, "the embedding probe runs before a topic fit"
end

Then("the probe passes") do
  raise NotImplementedError, "the probe passes"
end

Then("the topic fit proceeds") do
  raise NotImplementedError, "the topic fit proceeds"
end

Given("a conversation with speakers {string} and {string} whose clauses span the six process types") do
  raise NotImplementedError, "a conversation with speakers \"A\" and \"B\" whose clauses span the six process types"
end

When("the process-mix analysis runs") do
  raise NotImplementedError, "the process-mix analysis runs"
end

Then("the report gives, for each speaker, the six process-type proportions") do
  raise NotImplementedError, "the report gives, for each speaker, the six process-type proportions"
end

Then("the report gives, for each speaker, a deviation from the conversation's material baseline") do
  raise NotImplementedError, "the report gives, for each speaker, a deviation from the conversation's material baseline"
end

Given("a speaker whose six proportions equal the material baseline") do
  raise NotImplementedError, "a speaker whose six proportions equal the material baseline"
end

Then("that speaker's deviation is {int}") do
  raise NotImplementedError, "that speaker's deviation is 0"
end

Given("clauses from speaker {string} of which some have source {string} and the rest have source {string}") do
  raise NotImplementedError, "clauses from speaker \"A\" of which some have source \"heuristic\" and the rest have source \"llm\""
end

Then("only the llm clauses are counted for speaker {string}") do
  raise NotImplementedError, "only the llm clauses are counted for speaker \"A\""
end

Given("speaker {string} whose only clauses have source {string}") do
  raise NotImplementedError, "speaker \"C\" whose only clauses have source \"heuristic\""
end

Then("speaker {string} is reported as having no data") do
  raise NotImplementedError, "speaker \"C\" is reported as having no data"
end

Then("speaker {string} has no deviation value") do
  raise NotImplementedError, "speaker \"C\" has no deviation value"
end

Given("sections at 00:00, 00:03 and 00:09 in one conversation") do
  raise NotImplementedError, "sections at 00:00, 00:03 and 00:09 in one conversation"
end

When("the gap analysis computes pauses") do
  raise NotImplementedError, "the gap analysis computes pauses"
end

Then("the pauses are {int} seconds and {int} seconds") do
  raise NotImplementedError, "the pauses are 180 seconds and 360 seconds"
end

Then("no pause is computed across two conversations") do
  raise NotImplementedError, "no pause is computed across two conversations"
end

Given("a conversation whose pauses are {int}, {int}, {int}, {int} and {int} seconds") do
  raise NotImplementedError, "a conversation whose pauses are 60, 120, 180, 240 and 300 seconds"
end

Given("a floor of {int} seconds") do
  raise NotImplementedError, "a floor of 0 seconds"
end

When("the gap analysis sets its long-pause threshold for that conversation") do
  raise NotImplementedError, "the gap analysis sets its long-pause threshold for that conversation"
end

Then(/\Athe\ threshold\ is\ 240\ seconds\z/) do
  raise NotImplementedError, "the threshold is 240 seconds"
end

Given("the default floor of {int} seconds") do
  raise NotImplementedError, "the default floor of 600 seconds"
end

Then(/\Athe\ threshold\ is\ 600\ seconds\z/) do
  raise NotImplementedError, "the threshold is 600 seconds"
end

Then("the 300-second pause is not a long pause") do
  raise NotImplementedError, "the 300-second pause is not a long pause"
end

Given("a configured floor of {int} seconds") do
  raise NotImplementedError, "a configured floor of 300 seconds"
end

Then(/\Athe\ threshold\ is\ 300\ seconds\z/) do
  raise NotImplementedError, "the threshold is 300 seconds"
end

Then("a pause of {int} seconds is a long pause") do
  raise NotImplementedError, "a pause of 301 seconds is a long pause"
end

Given("TenorTracker#detect_significant_shifts flags sections {int} and {int} in a conversation") do
  raise NotImplementedError, "TenorTracker#detect_significant_shifts flags sections 3 and 7 in a conversation"
end

When("the gap analysis collects tenor spikes") do
  raise NotImplementedError, "the gap analysis collects tenor spikes"
end

Then("the spikes are sections {int} and {int}") do
  raise NotImplementedError, "the spikes are sections 3 and 7"
end

Given("{int} sections follow a long pause, of which {int} are tenor spikes") do
  raise NotImplementedError, "4 sections follow a long pause, of which 3 are tenor spikes"
end

Given("{int} sections follow no long pause, of which {int} is a tenor spike") do
  raise NotImplementedError, "4 sections follow no long pause, of which 1 is a tenor spike"
end

When("the gap analysis runs its test") do
  raise NotImplementedError, "the gap analysis runs its test"
end

Then("the test is Fisher exact") do
  raise NotImplementedError, "the test is Fisher exact"
end

Then("the two-sided p-value is {float} to four decimal places") do
  raise NotImplementedError, "the two-sided p-value is 0.4857 to four decimal places"
end

Then("the report gives both group counts") do
  raise NotImplementedError, "the report gives both group counts"
end

Given("a 2x2 table of spike and non-spike counts after long pauses and after other pauses in which an expected cell count is below {int}") do
  raise NotImplementedError, "a 2x2 table of spike and non-spike counts after long pauses and after other pauses in which an expected cell count is below 5"
end

When("the gap analysis runs its test with seed {int}") do
  raise NotImplementedError, "the gap analysis runs its test with seed 7"
end

Then("the report names the permutation test as the test used") do
  raise NotImplementedError, "the report names the permutation test as the test used"
end

Then("a repeated run with seed {int} reports the same p-value") do
  raise NotImplementedError, "a repeated run with seed 7 reports the same p-value"
end

Given(/\A5\ pairs\ \(1,2\),\ \(2,4\),\ \(3,6\),\ \(4,8\)\ and\ \(5,10\)\ of\ tenor\ and\ coherence\z/) do
  raise NotImplementedError, "5 pairs (1,2), (2,4), (3,6), (4,8) and (5,10) of tenor and coherence"
end

When("the tenor-coherence correlation runs") do
  raise NotImplementedError, "the tenor-coherence correlation runs"
end

Then("the coefficient is {float}") do
  raise NotImplementedError, "the coefficient is 1.0"
end

Then("the p-value is a number from {int} to {int}") do
  raise NotImplementedError, "the p-value is a number from 0 to 1"
end

Then(/\An\ is\ 5\z/) do
  raise NotImplementedError, "n is 5"
end

Given("tenor values {int}, {int}, {int}, {int} and coherence values {int}, {int}, {int}, {int}") do
  raise NotImplementedError, "tenor values 1, 2, 2, 3 and coherence values 1, 2, 3, 4"
end

Then("the coefficient is {float} to four decimal places") do
  raise NotImplementedError, "the coefficient is 0.9487 to four decimal places"
end

Given("{int} pairs of which one has a null tenor and one has a null coherence score") do
  raise NotImplementedError, "6 pairs of which one has a null tenor and one has a null coherence score"
end

Then(/\An\ is\ 4\z/) do
  raise NotImplementedError, "n is 4"
end

Given("loaded conversations that contain {int} sections with both avg_tenor and semantic_coherence_score non-null") do
  raise NotImplementedError, "loaded conversations that contain 17 sections with both avg_tenor and semantic_coherence_score non-null"
end

When("the eval:tenor_coherence task runs") do
  raise NotImplementedError, "the eval:tenor_coherence task runs"
end

Then("the report states a coefficient, a p-value and n equal to {int}") do
  raise NotImplementedError, "the report states a coefficient, a p-value and n equal to 17"
end

Then("n equals the count of non-null pairs computed independently from the same data") do
  raise NotImplementedError, "n equals the count of non-null pairs computed independently from the same data"
end

When("eval:tenor_coherence, eval:process_mix and eval:gap_analysis are each run") do
  raise NotImplementedError, "eval:tenor_coherence, eval:process_mix and eval:gap_analysis are each run"
end

Then(%r{\Aeach\ run\ writes\ a\ markdown\ report\ and\ a\ JSON\ report\ under\ output/eval/\z}) do
  raise NotImplementedError, "each run writes a markdown report and a JSON report under output/eval/"
end

Then("each report is named after its task") do
  raise NotImplementedError, "each report is named after its task"
end

Given(%r{\Aoutput/eval/nd-11\ through\ output/eval/nd-14\ are\ present\z}) do
  raise NotImplementedError, "output/eval/nd-11 through output/eval/nd-14 are present"
end

When("eval:process_mix runs") do
  raise NotImplementedError, "eval:process_mix runs"
end

Then(%r{\Athe\ conversation\ data\ is\ read\ from\ output/eval/nd-<n>/conversation_analysis\.json\ for\ n\ in\ 11,\ 12,\ 13\ and\ 14\z}) do
  raise NotImplementedError, "the conversation data is read from output/eval/nd-<n>/conversation_analysis.json for n in 11, 12, 13 and 14"
end

Then("the report lists conversations {int}, {int}, {int} and {int} as used") do
  raise NotImplementedError, "the report lists conversations 11, 12, 13 and 14 as used"
end

Given(%r{\Aoutput/eval/nd-11\ is\ present\ and\ output/eval/nd-12,\ nd-13\ and\ nd-14\ are\ absent\z}) do
  raise NotImplementedError, "output/eval/nd-11 is present and output/eval/nd-12, nd-13 and nd-14 are absent"
end

When("eval:tenor_coherence runs") do
  raise NotImplementedError, "eval:tenor_coherence runs"
end

Then("the task exits with status {int}") do
  raise NotImplementedError, "the task exits with status 0"
end

Then("the report lists conversations {int}, {int} and {int} as missing") do
  raise NotImplementedError, "the report lists conversations 12, 13 and 14 as missing"
end

Then("the report's n counts only data from conversation {int}") do
  raise NotImplementedError, "the report's n counts only data from conversation 11"
end

Given(%r{\Aoutput/eval/nd-11\ through\ output/eval/nd-14\ are\ all\ absent\z}) do
  raise NotImplementedError, "output/eval/nd-11 through output/eval/nd-14 are all absent"
end

When("eval:gap_analysis runs") do
  raise NotImplementedError, "eval:gap_analysis runs"
end

Then("the task exits with a non-zero status") do
  raise NotImplementedError, "the task exits with a non-zero status"
end

Then(%r{\Athe\ message\ names\ the\ dataset\ path\ output/eval\z}) do
  raise NotImplementedError, "the message names the dataset path output/eval"
end

When("the TUI starts") do
  raise NotImplementedError, "the TUI starts"
end

Then("the tab bar shows five tabs") do
  raise NotImplementedError, "the tab bar shows five tabs"
end

Then("the fifth tab is the analyses tab") do
  raise NotImplementedError, "the fifth tab is the analyses tab"
end

Then("pressing {int} switches to it") do
  raise NotImplementedError, "pressing 5 switches to it"
end

Given(%r{\Atwo\ tenor-coherence\ reports\ in\ output/eval/\ with\ different\ timestamps\z}) do
  raise NotImplementedError, "two tenor-coherence reports in output/eval/ with different timestamps"
end

When("the analyses tab renders") do
  raise NotImplementedError, "the analyses tab renders"
end

Then("it shows the coefficient, p-value and n from the newer report") do
  raise NotImplementedError, "it shows the coefficient, p-value and n from the newer report"
end

Given(%r{\Ano\ gap-analysis\ report\ exists\ in\ output/eval/\z}) do
  raise NotImplementedError, "no gap-analysis report exists in output/eval/"
end

Then("the gap-analysis panel shows {string} and names eval:gap_analysis") do
  raise NotImplementedError, "the gap-analysis panel shows \"not run yet\" and names eval:gap_analysis"
end

When("a key event is passed to Program.update with the analyses tab active") do
  raise NotImplementedError, "a key event is passed to Program.update with the analyses tab active"
end

Then("the result is a new immutable state") do
  raise NotImplementedError, "the result is a new immutable state"
end

Then("at most one command is returned") do
  raise NotImplementedError, "at most one command is returned"
end

Then("the tab reads no file itself; any read happens inside the command") do
  raise NotImplementedError, "the tab reads no file itself; any read happens inside the command"
end

Given(/\ASFL_LOG_TARGET\ is\ "stderr"\z/) do
  raise NotImplementedError, "SFL_LOG_TARGET is \"stderr\""
end

Given("the sidecar exits once with status {int} during a request") do
  raise NotImplementedError, "the sidecar exits once with status 1 during a request"
end

When("the client restarts the sidecar") do
  raise NotImplementedError, "the client restarts the sidecar"
end

Then("one log entry carries the fields component {string}, attempt {int} and exit_status {int}") do
  raise NotImplementedError, "one log entry carries the fields component \"bertopic_sidecar\", attempt 1 and exit_status 1"
end

Then("the log entry carries the SFL_RUN_ID field") do
  raise NotImplementedError, "the log entry carries the SFL_RUN_ID field"
end

Then("the log entry message is a fixed string containing no interpolated values") do
  raise NotImplementedError, "the log entry message is a fixed string containing no interpolated values"
end

Given("the first attempt falls below the coverage gate") do
  raise NotImplementedError, "the first attempt falls below the coverage gate"
end

Then("one log entry carries the fields attempt {int}, nr_topics, min_topic_size and coverage") do
  raise NotImplementedError, "one log entry carries the fields attempt 2, nr_topics, min_topic_size and coverage"
end

Then("the field values are the values sent and measured, not text built into the message") do
  raise NotImplementedError, "the field values are the values sent and measured, not text built into the message"
end

Given(/\ASFL_LOG_TARGET\ is\ "stderr,journald"\z/) do
  raise NotImplementedError, "SFL_LOG_TARGET is \"stderr,journald\""
end

Then("the restart log entry appears on stderr") do
  raise NotImplementedError, "the restart log entry appears on stderr"
end

Then("it appears in journalctl with the same SFL_RUN_ID") do
  raise NotImplementedError, "it appears in journalctl with the same SFL_RUN_ID"
end

When(/\Athe\ line\ \{"id":\ "x",\ "type":\ "bertopic",\ "texts":\ \[\ is\ written\ to\ stdin\z/) do
  raise NotImplementedError, "the line {\"id\": \"x\", \"type\": \"bertopic\", \"texts\": [ is written to stdin"
end

Then("one error line with id null and an {string} message is written") do
  raise NotImplementedError, "one error line with id null and an \"error\" message is written"
end

Then("the error message does not repeat the malformed line") do
  raise NotImplementedError, "the error message does not repeat the malformed line"
end

When("a valid bertopic request is written next") do
  raise NotImplementedError, "a valid bertopic request is written next"
end

Then("it is answered normally") do
  raise NotImplementedError, "it is answered normally"
end

Given("the client has sent request {string}") do
  raise NotImplementedError, "the client has sent request \"req-7\""
end

When("the sidecar writes a response line with id {string} and no line with id {string} arrives before the client timeout") do
  raise NotImplementedError, "the sidecar writes a response line with id \"req-6\" and no line with id \"req-7\" arrives before the client timeout"
end

Then("the client raises a typed sidecar error") do
  raise NotImplementedError, "the client raises a typed sidecar error"
end

Then("the {string} response is not returned as a result") do
  raise NotImplementedError, "the \"req-6\" response is not returned as a result"
end

Given("a request whose serialized size exceeds the client's documented maximum request size") do
  raise NotImplementedError, "a request whose serialized size exceeds the client's documented maximum request size"
end

When("fit is called with those texts") do
  raise NotImplementedError, "fit is called with those texts"
end

Then("fit raises a typed error that names the size limit and the measured size") do
  raise NotImplementedError, "fit raises a typed error that names the size limit and the measured size"
end

Then("the sidecar receives no bytes for that request") do
  raise NotImplementedError, "the sidecar receives no bytes for that request"
end

Then("the sidecar process is still running") do
  raise NotImplementedError, "the sidecar process is still running"
end

Given("the sidecar exits with status {int} after reading a request and before writing a response") do
  raise NotImplementedError, "the sidecar exits with status 1 after reading a request and before writing a response"
end

When("fit is called") do
  raise NotImplementedError, "fit is called"
end

Then("the client starts a new sidecar process and resends the request once") do
  raise NotImplementedError, "the client starts a new sidecar process and resends the request once"
end

Then("if the second attempt also crashes, fit raises a typed sidecar error that names exit status {int}") do
  raise NotImplementedError, "if the second attempt also crashes, fit raises a typed sidecar error that names exit status 1"
end

Then("no partial result is returned") do
  raise NotImplementedError, "no partial result is returned"
end

When("fit is called with {int} texts and {int} embedding vectors") do
  raise NotImplementedError, "fit is called with 5 texts and 4 embedding vectors"
end

Then("fit raises a typed error that names {int} and {int}") do
  raise NotImplementedError, "fit raises a typed error that names 5 and 4"
end

Then("no bertopic request is written to the sidecar") do
  raise NotImplementedError, "no bertopic request is written to the sidecar"
end

Given("SFL_TASK_EMBEDDING_PROVIDER is {string} and SFL_TASK_EMBEDDING_MODEL is {string}") do
  raise NotImplementedError, "SFL_TASK_EMBEDDING_PROVIDER is \"ollama\" and SFL_TASK_EMBEDDING_MODEL is \"embeddinggemma-2:440m\""
end

Given("the configured Ollama endpoint refuses connections") do
  raise NotImplementedError, "the configured Ollama endpoint refuses connections"
end

Then("a typed embedding error is raised") do
  raise NotImplementedError, "a typed embedding error is raised"
end

Then("its message names {string}, {string} and the endpoint URL") do
  raise NotImplementedError, "its message names \"ollama\", \"embeddinggemma-2:440m\" and the endpoint URL"
end

Then("no topic fit is attempted") do
  raise NotImplementedError, "no topic fit is attempted"
end

Then("no embeddings are produced") do
  raise NotImplementedError, "no embeddings are produced"
end

Given("the Ollama server is reachable and lists no model named {string}") do
  raise NotImplementedError, "the Ollama server is reachable and lists no model named \"embeddinggemma-2:440m\""
end

Then("its message names {string}, {string}, the endpoint URL and the instruction to run ollama pull") do
  raise NotImplementedError, "its message names \"ollama\", \"embeddinggemma-2:440m\", the endpoint URL and the instruction to run ollama pull"
end

Given("the Ollama server answers an embedding request for {int} texts with an error body") do
  raise NotImplementedError, "the Ollama server answers an embedding request for 5 texts with an error body"
end

Given("a second embedding request for {int} texts is answered with {int} vectors") do
  raise NotImplementedError, "a second embedding request for 5 texts is answered with 3 vectors"
end

When("each reply is received") do
  raise NotImplementedError, "each reply is received"
end

Then("each reply raises a typed embedding error") do
  raise NotImplementedError, "each reply raises a typed embedding error"
end

Then("neither reply is passed to the sidecar as embeddings") do
  raise NotImplementedError, "neither reply is passed to the sidecar as embeddings"
end

Then("no empty embedding vector is produced") do
  raise NotImplementedError, "no empty embedding vector is produced"
end

Given("SFL_EMBEDDING_TIMEOUT_SECONDS is {int}") do
  raise NotImplementedError, "SFL_EMBEDDING_TIMEOUT_SECONDS is 2"
end

Given("the Ollama server accepts the connection and never responds") do
  raise NotImplementedError, "the Ollama server accepts the connection and never responds"
end

When("the embedding probe runs") do
  raise NotImplementedError, "the embedding probe runs"
end

Then("the call ends within {int} seconds") do
  raise NotImplementedError, "the call ends within 3 seconds"
end

Then("a typed embedding error names the timeout and the endpoint") do
  raise NotImplementedError, "a typed embedding error names the timeout and the endpoint"
end

Given("a section whose text contains {string}") do
  raise NotImplementedError, "a section whose text contains \"CONFIDENTIAL-PHRASE-7731\""
end

Given("the Ollama server refuses connections") do
  raise NotImplementedError, "the Ollama server refuses connections"
end

When("that section is embedded") do
  raise NotImplementedError, "that section is embedded"
end

Then("the raised error names provider, model and endpoint") do
  raise NotImplementedError, "the raised error names provider, model and endpoint"
end

Then("the error message and the log entry do not contain {string}") do
  raise NotImplementedError, "the error message and the log entry do not contain \"CONFIDENTIAL-PHRASE-7731\""
end

Given(/\Aa\ fit\ for\ document\ key\ "x'\);\ DROP\ TABLE\ topic_models;--"\z/) do
  raise NotImplementedError, "a fit for document key \"x'); DROP TABLE topic_models;--\""
end

Then("the topic_models table still exists") do
  raise NotImplementedError, "the topic_models table still exists"
end

Then("one row exists whose document key is that exact string") do
  raise NotImplementedError, "one row exists whose document key is that exact string"
end

Given("the database rejects the insert of topic_words during the store") do
  raise NotImplementedError, "the database rejects the insert of topic_words during the store"
end

Then("a typed store error is raised") do
  raise NotImplementedError, "a typed store error is raised"
end

Then("no topic_models row exists for that run id") do
  raise NotImplementedError, "no topic_models row exists for that run id"
end

Given("two fits for the same document key are stored by two runs with different SFL_RUN_ID values") do
  raise NotImplementedError, "two fits for the same document key are stored by two runs with different SFL_RUN_ID values"
end

Then("two rows exist") do
  raise NotImplementedError, "two rows exist"
end

Then("each row's run id equals the SFL_RUN_ID of the run that wrote it") do
  raise NotImplementedError, "each row's run id equals the SFL_RUN_ID of the run that wrote it"
end

Then("each row has its own created_at value") do
  raise NotImplementedError, "each row has its own created_at value"
end

When(%r{\Aeval:tenor_coherence\ is\ run\ with\ CONVERSATIONS\ "11,\.\./\.\./secrets"\z}) do
  raise NotImplementedError, "eval:tenor_coherence is run with CONVERSATIONS \"11,../../secrets\""
end

Then(%r{\Athe\ message\ names\ the\ rejected\ token\ "\.\./\.\./secrets"\z}) do
  raise NotImplementedError, "the message names the rejected token \"../../secrets\""
end

Then(%r{\Ano\ file\ outside\ output/eval/nd-<n>/\ is\ read\ or\ written\z}) do
  raise NotImplementedError, "no file outside output/eval/nd-<n>/ is read or written"
end

Given(%r{\Aoutput/eval/tenor_coherence\.md\ is\ a\ symlink\ to\ a\ file\ outside\ output/eval/\z}) do
  raise NotImplementedError, "output/eval/tenor_coherence.md is a symlink to a file outside output/eval/"
end

Then("the task exits with a non-zero status naming the report path") do
  raise NotImplementedError, "the task exits with a non-zero status naming the report path"
end

Then("the symlink target's content is byte-identical to before the run") do
  raise NotImplementedError, "the symlink target's content is byte-identical to before the run"
end

Given(%r{\Aa\ previous\ output/eval/process_mix\.md\ exists\z}) do
  raise NotImplementedError, "a previous output/eval/process_mix.md exists"
end

When("eval:process_mix is interrupted with SIGINT while writing") do
  raise NotImplementedError, "eval:process_mix is interrupted with SIGINT while writing"
end

Then(%r{\Aoutput/eval/process_mix\.md\ is\ byte-identical\ to\ the\ previous\ report\z}) do
  raise NotImplementedError, "output/eval/process_mix.md is byte-identical to the previous report"
end

Then(%r{\Ano\ temporary\ or\ partial\ report\ file\ remains\ under\ output/eval/\z}) do
  raise NotImplementedError, "no temporary or partial report file remains under output/eval/"
end

Given("a section whose text contains {string} in conversation {int}") do
  raise NotImplementedError, "a section whose text contains \"CONFIDENTIAL-PHRASE-7731\" in conversation 11"
end

When("all three eval tasks run") do
  raise NotImplementedError, "all three eval tasks run"
end

Then(%r{\Ano\ report\ under\ output/eval/\ contains\ "CONFIDENTIAL-PHRASE-7731"\z}) do
  raise NotImplementedError, "no report under output/eval/ contains \"CONFIDENTIAL-PHRASE-7731\""
end

Given(%r{\Aoutput/eval/tenor_coherence\.md\ is\ replaced\ with\ the\ text\ "\{not\ json"\z}) do
  raise NotImplementedError, "output/eval/tenor_coherence.md is replaced with the text \"{not json\""
end

Then("the tenor-coherence panel shows {string}") do
  raise NotImplementedError, "the tenor-coherence panel shows \"unreadable report\""
end

Then("the other panels and tabs keep working") do
  raise NotImplementedError, "the other panels and tabs keep working"
end

Given(/\Aa\ report\ line\ containing\ the\ escape\ sequence\ ESC\ \[2J\ and\ an\ OSC\ 52\ clipboard\ sequence\z/) do
  raise NotImplementedError, "a report line containing the escape sequence ESC [2J and an OSC 52 clipboard sequence"
end

Then("the sequences are not interpreted by the terminal") do
  raise NotImplementedError, "the sequences are not interpreted by the terminal"
end

Then("the screen is not cleared by the report content") do
  raise NotImplementedError, "the screen is not cleared by the report content"
end

Given(%r{\Aoutput/eval/gap_analysis\.md\ is\ a\ symlink\ to\ a\ file\ outside\ output/eval/\z}) do
  raise NotImplementedError, "output/eval/gap_analysis.md is a symlink to a file outside output/eval/"
end

Then("the gap-analysis panel shows {string}") do
  raise NotImplementedError, "the gap-analysis panel shows \"refused: symlink\""
end

Then("the symlink target's content is not displayed") do
  raise NotImplementedError, "the symlink target's content is not displayed"
end

Given(%r{\Aoutput/eval/process_mix\.md\ is\ 50\ MB\z}) do
  raise NotImplementedError, "output/eval/process_mix.md is 50 MB"
end

Then("at most the fixed byte limit is read") do
  raise NotImplementedError, "at most the fixed byte limit is read"
end

Then("the panel shows a truncation notice") do
  raise NotImplementedError, "the panel shows a truncation notice"
end
