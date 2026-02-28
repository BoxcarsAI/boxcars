# frozen_string_literal: true

module Boxcars
  # @abstract
  class Boxcar
    attr_reader :name, :description, :return_direct, :parameters

    SCHEMA_KEY_ALIASES = {
      additional_properties: "additionalProperties",
      one_of: "oneOf",
      any_of: "anyOf",
      all_of: "allOf"
    }.freeze

    TYPE_ALIASES = {
      int: "integer",
      integer: "integer",
      float: "number",
      double: "number",
      decimal: "number",
      number: "number",
      string: "string",
      bool: "boolean",
      boolean: "boolean",
      array: "array",
      object: "object",
      null: "null"
    }.freeze

    # A Boxcar is a container for a single tool to run.
    # @param name [String] The name of the boxcar. Defaults to classname.
    # @param description [String] A description of the boxcar.
    # @param return_direct [Boolean] If true, return the output of this boxcar directly, without merging it with the inputs.
    # @param parameters [Hash] The parameters for this boxcar.
    def initialize(description:, name: nil, return_direct: false, parameters: nil)
      @name = name || self.class.name
      @description = description || @name
      @return_direct = return_direct
      @parameters = parameters || { question: { type: :string, description: "the input question", required: true } }
    end

    # Input keys this chain expects.
    def input_keys
      [:question]
    end

    # Output keys this chain expects.
    def output_keys
      [:answer]
    end

    # Check that all inputs are present.
    # @param inputs [Hash] The inputs.
    # @raise [RuntimeError] If the inputs are not the same.
    def validate_inputs(inputs:)
      missing_keys = input_keys.reject { |key| key_present?(inputs, key) }
      raise "Missing some input keys: #{missing_keys}" if missing_keys.any?

      inputs
    end

    # check that all outputs are present
    # @param outputs [Array<String>] The output keys.
    # @raise [RuntimeError] If the outputs are not the same.
    def validate_outputs(outputs:)
      unexpected = outputs.reject do |key|
        output_keys.any? { |expected| same_key?(expected, key) } || same_key?(:log, key)
      end
      return if unexpected.empty?

      raise "Did not get output keys that were expected, got: #{outputs}. Expected: #{output_keys}"
    end

    # Run the core logic for one invocation.
    # @param inputs [Hash] Input values keyed by `input_keys`.
    # @return [Hash] Output values keyed by `output_keys`.
    def call(inputs:)
      raise NotImplementedError
    end

    # Apply the boxcar to a list of inputs.
    # Override this when a subclass can batch requests more efficiently.
    # @param input_list [Array<Hash>] The list of inputs.
    # @return [Array<Hash>] One output hash per input hash.
    def apply(input_list:)
      input_list.map { |inputs| call(inputs:) }
    end

    # Convenience wrapper around `conduct` that returns only the first output value.
    # @param args [Array] The positional arguments to pass to the boxcar.
    # @param kwargs [Hash] The keyword arguments to pass to the boxcar.
    # you can pass one or the other, but not both.
    # @return [Object] The first output value. If that value is a `Boxcars::Result`,
    #   this method returns `result.answer`.
    def run(*, **)
      rv = conduct(*, **)
      result = Result.extract(rv)
      return result.answer if result
      return rv.output_for(output_keys[0]) if rv.respond_to?(:output_for)
      return rv[output_keys[0]] if rv.is_a?(Hash)

      rv
    end

    # Convenience helper that returns the structured `Boxcars::Result` from `conduct`.
    # @param args [Array] The positional arguments to pass to the boxcar.
    # @param kwargs [Hash] The keyword arguments to pass to the boxcar.
    # @return [Boxcars::Result,nil] Extracted result when this boxcar returns structured output.
    def run_result(*, **)
      Result.extract(conduct(*, **))
    end

    # Alias for `run_result` to make intent explicit when callers want full context first.
    # @param args [Array] The positional arguments to pass to the boxcar.
    # @param kwargs [Hash] The keyword arguments to pass to the boxcar.
    # @return [Boxcars::Result,nil] Extracted result when this boxcar returns structured output.
    def conduct_result(*, **)
      run_result(*, **)
    end

    # Run the boxcar and return full input/output context.
    # @param args [Array] The positional arguments to pass to the boxcar.
    # @param kwargs [Hash] The keyword arguments to pass to the boxcar.
    # you can pass one or the other, but not both.
    # @return [Hash] A hash that includes original inputs and call outputs.
    def conduct(*, **)
      Boxcars.info "> Entering #{name}#run", :gray, style: :bold
      rv = depart(*, **)
      remember_history(rv)
      Boxcars.info "< Exiting #{name}#run", :gray, style: :bold
      rv
    end

    # helpers for conversation prompt building
    # assistant message
    def self.assi(*strs)
      [:assistant, strs.join]
    end

    # system message
    def self.syst(*strs)
      [:system, strs.join]
    end

    # user message
    def self.user(*strs)
      [:user, strs.join]
    end

    # history entries
    def self.hist
      [:history, ""]
    end

    def schema
      params = parameters.map do |name, info|
        "<param name=#{name.to_s.inspect} data-type=#{info[:type].to_s.inspect} required=\"#{info[:required] == true}\" " \
          "description=#{info[:description].inspect} />"
      end.join("\n")
      <<~SCHEMA.freeze
        <tool name="#{name}" description="#{description}">
          <params>
            #{params}
          </params>
        </tool>
      SCHEMA
    end

    # A provider-safe function/tool name for LLM tool-calling APIs.
    def tool_call_name(max_length: 64)
      sanitized = name.to_s.gsub(/[^\w-]+/, "_").gsub(/\A_+|_+\z/, "")
      sanitized = "boxcar" if sanitized.empty?
      sanitized = "boxcar_#{sanitized}" unless sanitized.match?(/\A[a-zA-Z_]/)
      sanitized[0, max_length]
    end

    # Convert legacy Boxcar parameter definitions into JSON Schema.
    def parameters_json_schema
      props = {}
      required = []

      parameters.each do |param_name, info|
        param_key = param_name.to_s
        props[param_key] = parameter_descriptor_to_json_schema(info)
        required << param_key if parameter_required?(info)
      end

      schema = {
        "type" => "object",
        "properties" => props,
        "additionalProperties" => false
      }
      schema["required"] = required if required.any?
      schema
    end

    # Provider-agnostic normalized tool definition.
    def tool_definition
      {
        name: tool_call_name,
        display_name: name,
        description: description,
        input_schema: parameters_json_schema
      }
    end

    # OpenAI-compatible tool spec shape (also usable by many compatible providers).
    def tool_spec
      {
        type: "function",
        function: {
          name: tool_call_name,
          description: description,
          parameters: parameters_json_schema
        }
      }
    end

    private

    def parameter_required?(info)
      return false unless info.is_a?(Hash)

      info[:required] == true || info["required"] == true
    end

    def parameter_descriptor_to_json_schema(info)
      return { "type" => normalize_json_type(info) } if info.is_a?(Symbol) || info.is_a?(String)

      return { "type" => "string" } unless info.is_a?(Hash)

      raw_schema = info[:json_schema] || info["json_schema"] || info[:schema] || info["schema"]
      return normalize_json_schema_fragment(raw_schema) if raw_schema

      schema = {}
      schema["type"] = normalize_json_type(info[:type] || info["type"] || "string")

      description = info[:description] || info["description"]
      schema["description"] = description if description

      info.each do |key, value|
        next if %i[type description required json_schema schema].include?(key)
        next if ["type", "description", "required", "json_schema", "schema"].include?(key)

        normalized_key = normalize_schema_key(key)
        schema[normalized_key] = normalize_json_schema_fragment(value)
      end

      schema
    end

    def normalize_json_schema_fragment(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, fragment_value), out|
          normalized_key = normalize_schema_key(key)
          out[normalized_key] =
            case normalized_key
            when "type"
              normalize_json_type(fragment_value)
            when "properties"
              if fragment_value.is_a?(Hash)
                fragment_value.each_with_object({}) do |(prop_name, prop_schema), props|
                  props[prop_name.to_s] = normalize_json_schema_fragment(prop_schema)
                end
              else
                normalize_json_schema_fragment(fragment_value)
              end
            when "required"
              fragment_value.is_a?(Array) ? fragment_value.map(&:to_s) : fragment_value
            else
              normalize_json_schema_fragment(fragment_value)
            end
        end
      when Array
        value.map { |item| normalize_json_schema_fragment(item) }
      when Symbol
        value.to_s
      else
        value
      end
    end

    def normalize_schema_key(key)
      SCHEMA_KEY_ALIASES.fetch(key.to_sym, key.to_s)
    end

    def normalize_json_type(type)
      TYPE_ALIASES.fetch(type.to_sym, type.to_s)
    rescue NoMethodError
      type.to_s
    end

    # remember the history of this boxcar. Take the current intermediate steps and
    # create a history that can be used on the next run.
    # @param current_results [Array<Hash>] The current results.
    def remember_history(current_results)
      return unless current_results[:intermediate_steps] && is_a?(Train)

      # insert conversation history into the prompt
      history = []
      history << Boxcar.user(key_and_value_text(question_prefix, current_results[:input]))
      current_results[:intermediate_steps].each do |action, obs|
        if action.is_a?(TrainAction)
          obs = Observation.new(status: :ok, note: obs) if obs.is_a?(String)
          next if obs.status != :ok

          history << Boxcar.assi("#{thought_prefix}#{action.log}", "\n",
                                 key_and_value_text(observation_prefix, obs.note))
        else
          Boxcars.error "Unknown action: #{action}", :red
        end
      end
      final_answer = key_and_value_text(final_answer_prefix, current_results[:output])
      history << Boxcar.assi(
        key_and_value_text(thought_prefix, "I know the final answer\n#{final_answer}\n"))
      prompt.add_history(history)
    end

    # Get an answer from the boxcar.
    def run_boxcar(inputs:, return_only_outputs: false)
      inputs = our_inputs(inputs)
      output = nil
      begin
        output = call(inputs:)
      rescue StandardError => e
        Boxcars.error "Error in #{name} boxcar#call: #{e}\nbt:#{e.backtrace[0..5].join("\n   ")}", :red
        Boxcars.error("Response Body: #{e.response[:body]}", :red) if e.respond_to?(:response) && !e.response.nil?
        raise e
      end
      unless output.is_a?(Hash)
        raise Boxcars::Error, "#{name}#call must return a Hash keyed by #{output_keys.inspect}, got #{output.class}"
      end
      validate_outputs(outputs: output.keys)
      return output if return_only_outputs

      ConductResult.new(inputs.merge(output))
    end

    # line up parameters and run boxcar
    def depart(*args, **kwargs)
      if kwargs.empty?
        raise Boxcars::ArgumentError, "run supports only one positional argument." if args.length != 1

        return run_boxcar(inputs: args[0])
      end

      return run_boxcar(inputs: kwargs) if args.empty?

      raise Boxcars::ArgumentError, "run supported with either positional or keyword arguments but not both. Got args" \
                                    ": #{args} and kwargs: #{kwargs}."
    end

    def our_inputs(inputs)
      if inputs.is_a?(String)
        Boxcars.info inputs, :blue # the question
        if input_keys.length != 1
          raise Boxcars::ArgumentError, "A single string input was passed in, but this boxcar expects " \
                                        "multiple inputs (#{input_keys}). When a boxcar expects " \
                                        "multiple inputs, please call it by passing in a hash, eg: `boxcar({'foo': 1, 'bar': 2})`"
        end
        inputs = { input_keys.first => inputs }
      end
      validate_inputs(inputs:)
    end

    def input_value(inputs, key)
      return nil unless inputs.is_a?(Hash)

      inputs[key] || inputs[key.to_s]
    end

    def key_present?(hash, key)
      key_variants(key).any? { |candidate| hash.key?(candidate) }
    end

    def same_key?(left, right)
      left_variants = key_variants(left)
      key_variants(right).any? { |candidate| left_variants.include?(candidate) }
    end

    def key_variants(key)
      case key
      when Symbol
        [key, key.to_s]
      when String
        [key, key.to_sym]
      else
        [key]
      end
    end

    # the default answer is the text passed in
    def get_answer(text)
      Result.from_text(text)
    end
  end
end

require "boxcars/observation"
require "boxcars/result"
require "boxcars/conduct_result"
require "boxcars/boxcar/engine_boxcar"
require "boxcars/boxcar/json_engine_boxcar"
require "boxcars/boxcar/xml_engine_boxcar"
require "boxcars/boxcar/calculator"
require "boxcars/boxcar/ruby_calculator"
require "boxcars/boxcar/google_search"
require "boxcars/boxcar/url_text"
require "boxcars/boxcar/wikipedia_search"
require "boxcars/boxcar/sql_base"
require "boxcars/boxcar/sql_active_record"
require "boxcars/boxcar/sql_sequel"
require "boxcars/boxcar/swagger"
require "boxcars/boxcar/active_record"
require "boxcars/vector_store"
require "boxcars/vector_search"
require "boxcars/boxcar/vector_answer"
