# frozen_string_literal: true

module Boxcars
  # Internal adapter that hides SDK-specific client method shapes from engines.
  #
  # This starts with a ruby-openai implementation to lock the adapter contract
  # before introducing the official OpenAI Ruby SDK backend.
  class OpenAIClientAdapter
    attr_reader :backend, :raw_client

    def self.build(access_token:, uri_base: nil, organization_id: nil, log_errors: nil, backend: nil)
      selected_backend = (backend || Boxcars.configuration.openai_client_backend || :official_openai).to_sym
      raw_client = Boxcars::OpenAICompatibleClient.build(
        access_token:,
        uri_base:,
        organization_id:,
        log_errors:,
        backend: selected_backend
      )
      new(raw_client:, backend: selected_backend)
    end

    def initialize(raw_client:, backend:)
      @raw_client = raw_client
      @backend = backend.to_sym
    end

    def chat_create(parameters:)
      case backend
      when :ruby_openai
        raw_client.chat(parameters: parameters)
      when :official_openai
        normalize_response(call_official_chat(parameters))
      else
        raise Boxcars::ConfigurationError, "Unsupported OpenAI adapter backend: #{backend.inspect}"
      end
    end

    def completions_create(parameters:)
      case backend
      when :ruby_openai
        raw_client.completions(parameters: parameters)
      when :official_openai
        normalize_response(call_official_completions(parameters))
      else
        raise Boxcars::ConfigurationError, "Unsupported OpenAI adapter backend: #{backend.inspect}"
      end
    end

    def responses_create(parameters:)
      case backend
      when :ruby_openai
        raise StandardError, "OpenAI Responses API not supported by installed ruby-openai gem. Upgrade ruby-openai to >7.0 version." unless supports_responses_api?

        raw_client.responses.create(parameters: parameters)
      when :official_openai
        raise StandardError, "OpenAI Responses API not supported by official_openai backend client." unless supports_responses_api?

        normalize_response(call_official_responses(parameters))
      else
        raise Boxcars::ConfigurationError, "Unsupported OpenAI adapter backend: #{backend.inspect}"
      end
    end

    def embeddings_create(parameters:)
      case backend
      when :ruby_openai
        raw_client.embeddings(parameters: parameters)
      when :official_openai
        normalize_response(call_official_embeddings(parameters))
      else
        raise Boxcars::ConfigurationError, "Unsupported OpenAI adapter backend: #{backend.inspect}"
      end
    end

    def supports_responses_api?
      case backend
      when :ruby_openai
        raw_client.respond_to?(:responses)
      when :official_openai
        raw_client.respond_to?(:responses)
      else
        false
      end
    end

    private

    def call_official_chat(parameters)
      unless raw_client.respond_to?(:chat)
        raise Boxcars::ConfigurationError, "official_openai backend client does not expose #chat"
      end

      legacy_result = try_legacy_parameters_call(raw_client, :chat, parameters)
      return legacy_result if legacy_result.is_a?(Hash)

      chat_resource = raw_client.chat
      return chat_resource if chat_resource.is_a?(Hash)

      if chat_resource.respond_to?(:completions)
        call_create(chat_resource.completions, parameters)
      elsif chat_resource.respond_to?(:create)
        call_create(chat_resource, parameters)
      else
        raise Boxcars::ConfigurationError, "official_openai backend chat resource does not support #create"
      end
    end

    def call_official_completions(parameters)
      unless raw_client.respond_to?(:completions)
        raise Boxcars::ConfigurationError, "official_openai backend client does not expose #completions"
      end

      legacy_result = try_legacy_parameters_call(raw_client, :completions, parameters)
      return legacy_result if legacy_result.is_a?(Hash)

      completions_resource = raw_client.completions
      return completions_resource if completions_resource.is_a?(Hash)

      call_create(completions_resource, parameters)
    end

    def call_official_responses(parameters)
      responses_resource = raw_client.responses
      call_create(responses_resource, parameters)
    end

    def call_official_embeddings(parameters)
      unless raw_client.respond_to?(:embeddings)
        raise Boxcars::ConfigurationError, "official_openai backend client does not expose #embeddings"
      end

      legacy_result = try_legacy_parameters_call(raw_client, :embeddings, parameters)
      return legacy_result if legacy_result.is_a?(Hash)

      embeddings_resource = raw_client.embeddings
      return embeddings_resource if embeddings_resource.is_a?(Hash)

      call_create(embeddings_resource, parameters)
    end

    def call_create(resource, parameters)
      create_method = resource.method(:create)
      if keyword_parameters?(create_method, :parameters)
        resource.create(parameters: parameters)
      else
        resource.create(**parameters)
      end
    end

    def try_legacy_parameters_call(client, method_name, parameters)
      client.public_send(method_name, parameters: parameters)
    rescue ArgumentError, NoMethodError
      nil
    end

    def keyword_parameters?(method_obj, keyword_name)
      method_obj.parameters.any? { |type, name| %i[key keyreq].include?(type) && name == keyword_name }
    end

    def normalize_response(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), memo|
          memo[k.to_s] = normalize_response(v)
        end
      when Array
        obj.map { |v| normalize_response(v) }
      else
        if obj.respond_to?(:to_h)
          normalize_response(obj.to_h)
        else
          obj
        end
      end
    end
  end
end
