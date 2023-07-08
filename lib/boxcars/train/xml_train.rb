# frozen_string_literal: true

require "nokogiri"

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
      super
    end

    def init_prefixes
      @thought_prefix ||= "<thought>"
      @observation_prefix ||= "<observation>"
      @final_answer_prefix ||= "<final_answer>"
      @answer_prefix ||= "<answer>"
      @question_prefix ||= "<question>"
    end

    def close_tag(tag)
      tag.to_s.sub("<", "</") if tag.to_s[0] == "<"
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional(_inputs)
      { boxcar_names: boxcar_names, boxcar_descriptions: boxcar_descriptions, next_actions: next_actions }.merge super
    end

    def build_output(text)
      if text =~ /#{close_tag(thought_prefix)}/
        "<data>#{thought_prefix}#{text}</data>"
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

    def parse_output(engine_output)
      doc = Nokogiri::XML("<data><thought>#{engine_output}\n</data>")
      keys = doc.element_children.first.element_children.map(&:name).map(&:to_sym)
      keys.to_h do |key|
        [key, doc.at_xpath("//#{key}")&.text]
      end
    end

    def child_keys(xnode)
      xnode.children.map(&:name).map(&:to_sym)
    end

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

      if final_answer.present?
        Result.new(status: :ok, answer: final_answer, explanation: final_answer)
      else
        # we have an unexpected output from the engine
        unless action.present? && action_input.present?
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
