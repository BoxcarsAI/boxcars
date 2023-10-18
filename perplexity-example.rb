require "debug"
require "dotenv/load"
require "boxcars"

# Boxcars.configuration.logger = Logger.new($stdout)

eng = Boxcars::Perplexityai.new
ctemplate = [
  Boxcars::Boxcar.syst("The user will type in a city name. Your job is to evaluate if the given city is a good place to live."),
  Boxcars::Boxcar.user("%<input>s")
]
conversation = Boxcars::Conversation.new(lines: ctemplate)

conversation_prompt = Boxcars::ConversationPrompt.new(conversation:, input_variables: [:input], other_inputs: [], output_variables: [:answer])

boxcar = Boxcars::EngineBoxcar.new(engine: eng, name: "City Helper", prompt: conversation_prompt, description: "Evaluate if a city is a good place to live.")
data = boxcar.run("Is Colorado City, Colorado a good place to live?")
debugger
# train = Boxcars.train.new(boxcars: [boxcar])
# data = train.run()
puts data
