# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # For Boxcars that use an engine to do their work.
  class JSONEngineBoxcar < EngineBoxcar
    # A JSON Engine Boxcar is a container for a single tool to run.
    attr_accessor :wanted_data, :data_description, :important, :symbolize,
                  :json_schema, :json_schema_name, :json_schema_strict

    # @param prompt [Boxcars::Prompt] The prompt to use for this boxcar with sane defaults.
    # @param wanted_data [String] The data to extract from.
    # @param data_description [String] The description of the data.
    # @param important [String] Any important instructions you want to give the LLM.
    # @param symbolize [Boolean] Symbolize the JSON results if true
    # @param kwargs [Hash] Additional arguments
    # @param json_schema [Hash,nil] Optional JSON Schema used to validate parsed output.
    # @param json_schema_name [String] Name used when rendering schema instructions.
    # @param json_schema_strict [Boolean] If true, reject outputs that violate schema.
    def initialize(prompt: nil, wanted_data: nil, data_description: nil, important: nil, symbolize: false,
                   json_schema: nil, json_schema_name: "boxcars_json_output", json_schema_strict: true, **kwargs)
      @wanted_data = wanted_data || "summarize the pertinent facts from the input data"
      @data_description = data_description || "the input data"
      @important = important
      @json_schema = json_schema
      @json_schema_name = json_schema_name
      @json_schema_strict = json_schema_strict
      the_prompt = prompt || default_prompt
      kwargs[:description] ||= "JSON Engine Boxcar"
      @symbolize = symbolize
      super(prompt: the_prompt, **kwargs)
    end

    def default_prompt
      stock_prompt = <<~SYSPR
        I will provide you with %<data_description>s.
        Your job is to extract information as described below.

        Your Output must be valid JSON with no lead in or post answer text in the output format below:

        Output Format:
          {
          %<wanted_data>s
          }
      SYSPR
      if json_schema
        stock_prompt += "\nYour output MUST conform to this JSON Schema:\n```json\n#{render_json_schema}\n```\n"
      end
      stock_prompt += "\n\nImportant:\n#{important}\n" unless important.to_s.empty?

      sprompt = format(stock_prompt, wanted_data:, data_description:)
      ctemplate = [
        Boxcar.syst(sprompt),
        Boxcar.user("%<input>s")
      ]
      conv = Conversation.new(lines: ctemplate)
      ConversationPrompt.new(conversation: conv, input_variables: [:input], other_inputs: [], output_variables: [:answer])
    end

    # Use native structured output when the engine supports it; otherwise
    # fall back to the existing prompt-driven JSON extraction flow.
    def generate(input_list:, current_conversation: nil)
      return super unless native_json_schema_generation_supported?

      stop = input_list[0][:stop]
      the_prompt = current_conversation ? prompt.with_conversation(current_conversation) : prompt
      generations = []
      raw_responses = []

      input_list.each do |inputs|
        raw = engine.client(
          prompt: the_prompt,
          inputs: inputs,
          **native_json_generation_kwargs(stop:)
        )
        raw_responses << raw
        generations << [Generation.new(text: extract_text_from_engine_response(raw), generation_info: {})]
      end

      EngineResult.new(
        generations: generations,
        engine_output: { raw_responses:, native_structured_output: true }
      )
    end

    # Parse out the action and input from the engine output.
    # @param engine_output [String] The output from the engine.
    # @return [Result] The result.
    def get_answer(engine_output)
      json_string = extract_json(engine_output)
      reply = JSON.parse(json_string, symbolize_names: symbolize)
      validation_errors = validate_against_json_schema(reply)
      if validation_errors.any? && json_schema_strict
        return Result.from_error("JSON schema validation error: #{validation_errors.join('; ')}")
      end

      Result.new(status: :ok, answer: reply, explanation: reply)
    rescue JSON::ParserError => e
      Boxcars.debug "JSON: #{engine_output}", :red
      Result.from_error("JSON parsing error: #{e.message}")
    rescue StandardError => e
      Result.from_error("Unexpected error: #{e.message}")
    end

    # get answer from parsed JSON
    # @param data [Hash] The data to extract from.
    # @return [Result] The result.
    def extract_answer(data)
      reply = data
      Result.new(status: :ok, answer: reply, explanation: reply)
    end

    private

    def render_json_schema
      JSON.pretty_generate(deep_stringify_schema(json_schema))
    rescue StandardError
      json_schema.to_json
    end

    def validate_against_json_schema(data)
      return [] unless json_schema.is_a?(Hash)

      schema = deep_stringify_schema(json_schema)
      validate_schema_node(schema, data, path: "$")
    end

    # Minimal JSON Schema validator for the common cases used by this gem.
    def validate_schema_node(schema, data, path:)
      return [] unless schema.is_a?(Hash)

      errors = []
      types = normalized_schema_types(schema["type"])
      errors.concat(validate_type(types, data, path)) if types
      return errors if errors.any?

      if schema.key?("enum")
        errors << "#{path}: expected one of #{schema['enum'].inspect}" unless schema["enum"].include?(data)
      end

      if data.is_a?(Hash)
        errors.concat(validate_object_schema(schema, data, path:))
      elsif data.is_a?(Array)
        errors.concat(validate_array_schema(schema, data, path:))
      end

      errors
    end

    def validate_object_schema(schema, data, path:)
      errors = []
      properties = schema["properties"].is_a?(Hash) ? schema["properties"] : {}
      required = schema["required"].is_a?(Array) ? schema["required"].map(&:to_s) : []

      required.each do |key|
        errors << "#{path}.#{key}: is required" unless data.key?(key) || data.key?(key.to_sym)
      end

      stringified_data = data.each_with_object({}) { |(k, v), out| out[k.to_s] = v }
      properties.each do |key, child_schema|
        next unless stringified_data.key?(key)

        errors.concat(validate_schema_node(child_schema, stringified_data[key], path: "#{path}.#{key}"))
      end

      if schema["additionalProperties"] == false
        extra_keys = stringified_data.keys - properties.keys
        extra_keys.each { |key| errors << "#{path}.#{key}: is not allowed" }
      end

      errors
    end

    def validate_array_schema(schema, data, path:)
      item_schema = schema["items"]
      return [] unless item_schema.is_a?(Hash)

      data.each_with_index.flat_map do |item, idx|
        validate_schema_node(item_schema, item, path: "#{path}[#{idx}]")
      end
    end

    def validate_type(types, data, path)
      return [] if types.any? { |type| type_matches?(type, data) }

      ["#{path}: expected #{types.join(' or ')}, got #{json_type_name(data)}"]
    end

    def normalized_schema_types(type)
      case type
      when nil
        nil
      when Array
        type.map { |t| t.to_s }
      else
        [type.to_s]
      end
    end

    def type_matches?(type, data)
      case type
      when "object"
        data.is_a?(Hash)
      when "array"
        data.is_a?(Array)
      when "string"
        data.is_a?(String)
      when "integer"
        data.is_a?(Integer)
      when "number"
        data.is_a?(Numeric)
      when "boolean"
        data == true || data == false
      when "null"
        data.nil?
      else
        true
      end
    end

    def json_type_name(data)
      case data
      when Hash then "object"
      when Array then "array"
      when String then "string"
      when Integer then "integer"
      when Numeric then "number"
      when TrueClass, FalseClass then "boolean"
      when NilClass then "null"
      else data.class.to_s
      end
    end

    def deep_stringify_schema(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), out|
          out[k.to_s] = deep_stringify_schema(v)
        end
      when Array
        value.map { |v| deep_stringify_schema(v) }
      else
        value
      end
    end

    def native_json_schema_generation_supported?
      return false unless json_schema.is_a?(Hash)
      return false unless engine.respond_to?(:supports?) && engine.supports?(:structured_output_json_schema)

      true
    end

    def native_json_generation_kwargs(stop:)
      kwargs = { response_format: native_json_response_format }
      kwargs[:stop] = stop if stop
      kwargs
    end

    def native_json_response_format
      {
        type: "json_schema",
        json_schema: {
          name: json_schema_name.to_s,
          strict: json_schema_strict,
          schema: deep_stringify_schema(json_schema)
        }
      }
    end

    def extract_text_from_engine_response(raw)
      return JSON.generate(raw) if raw.is_a?(Hash) && raw.key?(:parsed_json)

      if raw.is_a?(Hash)
        choices = raw["choices"] || raw[:choices]
        if choices.is_a?(Array)
          text = choices.filter_map do |choice|
            message = choice["message"] || choice[:message]
            content = message && (message["content"] || message[:content])
            if content.is_a?(String)
              content
            elsif content.is_a?(Array)
              content.filter_map do |part|
                next unless part.is_a?(Hash)

                part["text"] || part[:text] || part.dig("text", "value") || part.dig(:text, :value)
              end.join
            else
              choice["text"] || choice[:text]
            end
          end.join("\n").strip
          return text unless text.empty?
        end

        output_text = raw["output_text"] || raw[:output_text]
        return output_text if output_text.is_a?(String)
      end

      if engine.respond_to?(:extract_answer, true)
        extracted = engine.send(:extract_answer, raw)
        return extracted if extracted.is_a?(String)

        return JSON.generate(extracted) if extracted.is_a?(Hash) || extracted.is_a?(Array)
      end

      raw.to_s
    end

    def extract_json(text)
      # Escape control characters (U+0000 to U+001F)
      text = text.gsub(/[\u0000-\u001F]/, '')
      # first strip hidden characters
      # text = text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

      # sometimes the LLM adds text in front of the JSON output, so let's strip it here
      json_start = text.index("{")
      json_end = text.rindex("}")
      text[json_start..json_end]
    end

    def extract_json2(text)
      # Match the outermost JSON object
      match = text.match(/\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}/)
      raise StandardError, "No valid JSON object found in the output" unless match

      match[0]
    end
  end
end
