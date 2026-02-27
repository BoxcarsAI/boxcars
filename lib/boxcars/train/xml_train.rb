# frozen_string_literal: true

# base class for all XML trains
module Boxcars
  # A Train using XML for prompting and execution.
  class XMLTrain < Train
    # A Train will use a engine to run a series of boxcars.
    # @param boxcars [Array<Boxcars::Boxcar>] The boxcars to run.
    # @param prompt [Boxcars::Prompt] The prompt to use.
    # @param engine [Boxcars::Engine] The engine to use for this train.
    # @param kwargs [Hash] Additional arguments including: name, description, top_k, return_direct, and stop
    # @abstract
    def initialize(boxcars:, prompt:, engine: nil, **kwargs)
      @using_xml = true
      super
    end

    def init_prefixes
      @thought_prefix ||= "<thought>"
      @observation_prefix ||= "<observation>"
      @final_answer_prefix ||= "<final_answer>"
      @question_prefix ||= "<question>"
      @output_prefix ||= "<output>"
    end

    def close_tag(tag)
      tag.to_s.sub("<", "</") if tag.to_s[0] == "<"
    end

    # the xml to describe the boxcars
    def boxcars_xml
      schema = boxcars.map(&:schema).join("\n")
      "<boxcars>\n#{schema}</boxcars>"
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional(_inputs)
      { boxcars_xml:, next_actions: }.merge super
    end

    def build_output(text)
      if text.end_with?("</usetool>")
        "<data>#{engine_prefix}#{text}</output></data>"
      elsif text =~ /#{close_tag(thought_prefix)}/
        "<data>#{engine_prefix}#{text}</data>"
      else
        "<data>#{text}</data>"
      end
    end

    # Extract the boxcar and input from the engine output.
    # @param text [String] The output from the engine.
    # @return [Array<Boxcars::Boxcar, String>] The boxcar and input.
    def extract_boxcar_and_input(text)
      get_action_and_input(engine_output: build_output(text))
    rescue StandardError => e
      Boxcars.debug("Error: #{e.message}", :red)
      [:error, e.message]
    end

    private

    # get next action and input using an XNode
    # @param xnode [XNode] The XNode to use.
    # @return [Array<String, String>] The action and input.
    def xn_get_action_and_input(xnode)
      action = xnode.xtext("//action")
      action_input = xnode.xtext("//action_input")
      thought = xnode.xtext("//thought")
      final_answer = xnode.xtext("//final_answer")

      # the thought should be the frist line here if it doesn't start with "Action:"
      Boxcars.debug("Thought: #{thought}", :yellow)

      if final_answer && !final_answer.to_s.strip.empty?
        Result.new(status: :ok, answer: final_answer, explanation: final_answer)
      else
        # we have an unexpected output from the engine
        unless action && !action.to_s.strip.empty? && action_input && !action_input.to_s.strip.empty?
          return [:error, "You gave me an improperly formatted answer or didn't use tags."]
        end

        Boxcars.debug("Action: #{action}\nAction Input: #{action_input}", :yellow)
        [action, action_input]
      end
    end

    # Parse out the action and input from the engine output.
    # @param engine_output [String] The output from the engine.
    # @return [Array<String>] The action and input.
    def get_action_and_input(engine_output:)
      xn_get_action_and_input(XNode.from_xml(engine_output))
    end
  end
end
