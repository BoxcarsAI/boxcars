require "debug"
require "dotenv/load"
require "boxcars"

# Boxcars.configuration.logger = Logger.new($stdout)

eng = Boxcars::Perplexityai.new
# eng = Boxcars::Openai.new(model: "gpt-4")
ctemplate = [
  Boxcars::Boxcar.syst("The user will type in a city name. Your job is to evaluate if the given city is a good place to live. Build a comprehensive report about livability, weather, cost of living, crime rate, drivability, walkability, and bike ability, and direct flights. In the final answer, for the first paragraph, summarize the pros and cons of living in the city followed by the background information and links for the research. Finalize your answer with an overall grade from A to F on the city."),
  Boxcars::Boxcar.user("%<input>s")
]
conversation = Boxcars::Conversation.new(lines: ctemplate)

conversation_prompt = Boxcars::ConversationPrompt.new(conversation:, input_variables: [:input], other_inputs: [], output_variables: [:answer])

boxcar = Boxcars::EngineBoxcar.new(engine: eng, name: "City Helper", prompt: conversation_prompt, description: "Evaluate if a city is a good place to live.")
data = boxcar.run(ARGV.fetch(0, "San Francisco"))
# train = Boxcars.train.new(boxcars: [boxcar])
# data = train.run()
# debugger
puts data
