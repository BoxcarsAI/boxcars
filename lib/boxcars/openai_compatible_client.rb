# frozen_string_literal: true

require "openai"

module Boxcars
  # Centralized factory for OpenAI-compatible clients used by multiple engines
  # (OpenAI, Groq, Ollama, Gemini-compatible endpoints, etc.).
  module OpenAICompatibleClient
    # Adds a small stable surface used by engines (`*_create` methods) directly on
    # top of the official OpenAI::Client instance.
    module ClientMethods
      def chat_create(parameters:)
        OpenAICompatibleClient.normalize_response(OpenAICompatibleClient.call_chat(self, parameters))
      end

      def completions_create(parameters:)
        OpenAICompatibleClient.normalize_response(OpenAICompatibleClient.call_completions(self, parameters))
      end

      def responses_create(parameters:)
        OpenAICompatibleClient.normalize_response(OpenAICompatibleClient.call_responses(self, parameters))
      end

      def embeddings_create(parameters:)
        OpenAICompatibleClient.normalize_response(OpenAICompatibleClient.call_embeddings(self, parameters))
      end

      def supports_responses_api?
        respond_to?(:responses)
      end
    end

    class << self
      def official_client_builder
        @official_client_builder
      end

      def official_client_builder=(builder)
        unless builder.nil? || builder.respond_to?(:call)
          raise Boxcars::ConfigurationError, "official_client_builder must be callable (Proc/lambda) or nil"
        end

        @official_client_builder = builder
      end
    end

    def self.build(access_token:, uri_base: nil, organization_id: nil, log_errors: nil)
      raw_client = build_official_openai_client(
        access_token:,
        uri_base:,
        organization_id:,
        log_errors:
      )

      decorate_client(raw_client)
    end

    def self.validate_client_configuration!
      builder = official_client_builder || Boxcars.configuration.openai_official_client_builder
      return true if builder
      return true if detect_official_client_class

      if official_client_requires_native?
        raise Boxcars::ConfigurationError,
              "Official OpenAI client path is configured in native-only mode, but no native official OpenAI client was detected."
      end

      raise Boxcars::ConfigurationError,
            "Official OpenAI client path selected but no official client builder is configured and no compatible OpenAI::Client was detected."
    end

    def self.configure_official_client_builder!(client_class: nil)
      klass = client_class || detect_official_client_class
      return false unless klass

      self.official_client_builder = lambda do |access_token:, uri_base:, organization_id:, log_errors:|
        build_with_official_client_class(
          klass:,
          access_token:,
          uri_base:,
          organization_id:,
          log_errors:
        )
      end
      true
    end

    def self.detect_official_client_class
      return nil unless defined?(::OpenAI::Client)

      klass = ::OpenAI::Client
      official_client_class?(klass) ? klass : nil
    end

    def self.official_client_class?(klass)
      init_params = klass.instance_method(:initialize).parameters
      has_api_key_kwarg = init_params.any? { |type, name| %i[key keyreq].include?(type) && name == :api_key }
      return true if has_api_key_kwarg

      chat_params = klass.instance_method(:chat).parameters
      chat_params.empty?
    rescue NameError
      false
    end

    # --------------------------------------------------------------------------
    # Request helpers used by ClientMethods
    # --------------------------------------------------------------------------
    def self.call_chat(client, parameters)
      unless client.respond_to?(:chat)
        raise Boxcars::ConfigurationError, "Official OpenAI client does not expose #chat"
      end

      chat_resource = client.chat
      return chat_resource if chat_resource.is_a?(Hash)

      if chat_resource.respond_to?(:completions)
        call_create(chat_resource.completions, parameters)
      elsif chat_resource.respond_to?(:create)
        call_create(chat_resource, parameters)
      else
        raise Boxcars::ConfigurationError, "Official OpenAI client chat resource does not support #create"
      end
    end

    def self.call_completions(client, parameters)
      unless client.respond_to?(:completions)
        raise Boxcars::ConfigurationError, "Official OpenAI client does not expose #completions"
      end

      completions_resource = client.completions
      return completions_resource if completions_resource.is_a?(Hash)

      call_create(completions_resource, parameters)
    end

    def self.call_responses(client, parameters)
      unless client.respond_to?(:responses)
        raise StandardError, "OpenAI Responses API not supported by the official OpenAI client."
      end

      call_create(client.responses, parameters)
    end

    def self.call_embeddings(client, parameters)
      unless client.respond_to?(:embeddings)
        raise Boxcars::ConfigurationError, "Official OpenAI client does not expose #embeddings"
      end

      embeddings_resource = client.embeddings
      return embeddings_resource if embeddings_resource.is_a?(Hash)

      call_create(embeddings_resource, parameters)
    end

    def self.normalize_response(obj)
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

    def self.decorate_client(client)
      client.extend(ClientMethods)
      client
    rescue TypeError
      raise Boxcars::ConfigurationError,
            "Official OpenAI client object must be extensible or already implement *_create methods."
    end

    private

    def self.build_official_openai_client(access_token:, uri_base: nil, organization_id: nil, log_errors: nil)
      builder = official_client_builder || Boxcars.configuration.openai_official_client_builder
      unless builder
        configure_official_client_builder!
        builder = official_client_builder
      end

      if builder
        return builder.call(
          access_token:,
          uri_base:,
          organization_id:,
          log_errors:
        )
      end

      raise Boxcars::ConfigurationError,
            "Official OpenAI client path requires an official client builder or a compatible OpenAI::Client class, " \
            "but none was detected."
    end

    def self.build_with_official_client_class(klass:, access_token:, uri_base:, organization_id:, log_errors:)
      candidates = [
        { api_key: access_token, base_url: uri_base, organization: organization_id, log_errors: log_errors },
        { api_key: access_token, base_url: uri_base, organization_id: organization_id, log_errors: log_errors },
        { api_key: access_token, uri_base: uri_base, organization: organization_id, log_errors: log_errors },
        { api_key: access_token, uri_base: uri_base, organization_id: organization_id, log_errors: log_errors },
        { api_key: access_token, base_url: uri_base, organization: organization_id },
        { api_key: access_token, base_url: uri_base, organization_id: organization_id },
        { api_key: access_token }
      ]

      errors = []
      candidates.each do |kwargs|
        begin
          return klass.new(**kwargs.compact)
        rescue ::ArgumentError => e
          errors << e.message
        end
      end

      raise Boxcars::ConfigurationError,
            "Failed to initialize official OpenAI client with detected class #{klass}. " \
            "Tried #{candidates.length} constructor variants. Last error: #{errors.last}"
    end

    def self.call_create(resource, parameters)
      create_method = resource.method(:create)
      if keyword_parameters?(create_method, :parameters)
        resource.create(parameters: parameters)
      else
        resource.create(**parameters)
      end
    end

    def self.keyword_parameters?(method_obj, keyword_name)
      method_obj.parameters.any? { |type, name| %i[key keyreq].include?(type) && name == keyword_name }
    end

    def self.official_client_requires_native?
      Boxcars.configuration.openai_official_require_native
    end

    private_class_method :build_official_openai_client
    private_class_method :detect_official_client_class, :official_client_class?, :build_with_official_client_class
    private_class_method :official_client_requires_native?
    private_class_method :call_create, :keyword_parameters?
  end
end
