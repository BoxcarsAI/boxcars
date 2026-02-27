# frozen_string_literal: true

require "openai"

module Boxcars
  # Centralized factory for OpenAI-compatible clients used by multiple engines
  # (OpenAI, Groq, Ollama, Gemini-compatible endpoints, etc.).
  #
  # This creates a migration seam so the official OpenAI Ruby SDK can be adopted
  # incrementally without rewriting each provider engine at the same time.
  module OpenAICompatibleClient
    SUPPORTED_BACKENDS = %i[ruby_openai official_openai].freeze
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

    def self.build(access_token:, uri_base: nil, organization_id: nil, log_errors: nil, backend: nil)
      selected_backend = normalize_backend(backend || Boxcars.configuration.openai_client_backend)

      case selected_backend
      when :ruby_openai
        build_ruby_openai_client(
          access_token:,
          uri_base:,
          organization_id:,
          log_errors:
        )
      when :official_openai
        build_official_openai_client(
          access_token:,
          uri_base:,
          organization_id:,
          log_errors:
        )
      else
        # normalize_backend currently guards this, but keep a defensive branch to avoid silent changes.
        raise Boxcars::ConfigurationError,
              "Unsupported openai_client_backend: #{selected_backend.inspect}"
      end
    end

    def self.normalize_backend(backend)
      normalized = (backend || :official_openai).to_sym
      return normalized if SUPPORTED_BACKENDS.include?(normalized)

      raise Boxcars::ConfigurationError,
            "Unsupported openai_client_backend: #{backend.inspect}. " \
            "Supported backends: #{SUPPORTED_BACKENDS.join(', ')}"
    end

    def self.validate_backend_configuration!(backend: nil)
      selected_backend = normalize_backend(backend || Boxcars.configuration.openai_client_backend)

      case selected_backend
      when :ruby_openai
        ensure_ruby_openai_backend_compatible!
        true
      when :official_openai
        builder = official_client_builder || Boxcars.configuration.openai_official_client_builder
        return true if builder
        return true if detect_official_client_class
        return true if !official_backend_requires_native? && detect_ruby_openai_client_class

        if official_backend_requires_native?
          raise Boxcars::ConfigurationError,
                "official_openai backend is configured in native-only mode, but no native official OpenAI client was detected."
        end

        raise Boxcars::ConfigurationError,
              "official_openai backend selected but no official client builder is configured and no compatible OpenAI::Client was detected."
      else
        raise Boxcars::ConfigurationError, "Unsupported openai_client_backend: #{selected_backend.inspect}"
      end
    end

    def self.build_ruby_openai_client(access_token:, uri_base: nil, organization_id: nil, log_errors: nil)
      ensure_ruby_openai_backend_compatible!
      args = { access_token: access_token }
      args[:uri_base] = uri_base if uri_base
      args[:organization_id] = organization_id if organization_id
      args[:log_errors] = log_errors unless log_errors.nil?
      ::OpenAI::Client.new(**args)
    end

    def self.build_official_openai_client(access_token:, uri_base: nil, organization_id: nil, log_errors: nil)
      builder = official_client_builder || Boxcars.configuration.openai_official_client_builder
      unless builder
        configure_official_client_builder!(allow_ruby_openai_bridge: !official_backend_requires_native?)
        builder = official_client_builder
      end

      if builder
        return builder.call(
          access_token: access_token,
          uri_base: uri_base,
          organization_id: organization_id,
          log_errors: log_errors
        )
      end

      raise Boxcars::ConfigurationError,
            "openai_client_backend=:official_openai requires an official client builder or a compatible OpenAI::Client class, " \
            "but none was detected."
    end

    def self.configure_official_client_builder!(client_class: nil, allow_ruby_openai_bridge: true)
      klass = client_class || detect_official_client_class
      if klass
        self.official_client_builder = lambda do |access_token:, uri_base:, organization_id:, log_errors:|
          build_with_official_client_class(
            klass:,
            access_token:,
            uri_base:,
            organization_id:,
            log_errors:
          )
        end
        return true
      end

      return false unless allow_ruby_openai_bridge

      compat_klass = detect_ruby_openai_client_class
      return false unless compat_klass

      warn_official_backend_compatibility_bridge_once!
      self.official_client_builder = lambda do |access_token:, uri_base:, organization_id:, log_errors:|
        build_with_ruby_openai_compat_class(
          klass: compat_klass,
          access_token: access_token,
          uri_base: uri_base,
          organization_id: organization_id,
          log_errors: log_errors
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
      has_access_token_kwarg = init_params.any? { |type, name| %i[key keyreq].include?(type) && name == :access_token }
      has_api_key_kwarg = init_params.any? { |type, name| %i[key keyreq].include?(type) && name == :api_key }

      return false if has_access_token_kwarg
      return true if has_api_key_kwarg

      chat_params = klass.instance_method(:chat).parameters
      chat_params.empty?
    rescue NameError
      false
    end

    def self.ruby_openai_client_class?(klass)
      init_params = klass.instance_method(:initialize).parameters
      return true if init_params.any? { |type, name| %i[key keyreq].include?(type) && name == :access_token }

      chat_params = klass.instance_method(:chat).parameters
      chat_params.any? { |type, name| %i[key keyreq].include?(type) && name == :parameters }
    rescue NameError
      false
    end

    def self.detect_ruby_openai_client_class
      return nil unless defined?(::OpenAI::Client)

      klass = ::OpenAI::Client
      ruby_openai_client_class?(klass) ? klass : nil
    end

    def self.ensure_ruby_openai_backend_compatible!
      return true unless defined?(::OpenAI::Client)
      return true if ruby_openai_client_class?(::OpenAI::Client)

      raise Boxcars::ConfigurationError,
            "openai_client_backend=:ruby_openai requires ruby-openai's OpenAI::Client (chat(parameters: ...)). " \
            "Detected a non-ruby-openai OpenAI::Client in this process."
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
        rescue ArgumentError => e
          errors << e.message
        end
      end

      raise Boxcars::ConfigurationError,
            "Failed to initialize official OpenAI client with detected class #{klass}. " \
            "Tried #{candidates.length} constructor variants. Last error: #{errors.last}"
    end

    def self.build_with_ruby_openai_compat_class(klass:, access_token:, uri_base:, organization_id:, log_errors:)
      candidates = [
        { access_token: access_token, uri_base: uri_base, organization_id: organization_id, log_errors: log_errors },
        { access_token: access_token, uri_base: uri_base, organization_id: organization_id },
        { access_token: access_token, uri_base: uri_base },
        { access_token: access_token }
      ]

      errors = []
      candidates.each do |kwargs|
        begin
          return klass.new(**kwargs.compact)
        rescue ArgumentError => e
          errors << e.message
        end
      end

      raise Boxcars::ConfigurationError,
            "Failed to initialize ruby-openai compatibility client class #{klass}. " \
            "Tried #{candidates.length} constructor variants. Last error: #{errors.last}"
    end

    def self.warn_official_backend_compatibility_bridge_once!
      return if @compatibility_bridge_warning_emitted

      message = "openai_client_backend=:official_openai is using ruby-openai compatibility bridge. " \
                "Configure openai_official_client_builder to force native official client wiring."
      if Boxcars.logger
        Boxcars.logger.warn(message)
      else
        warn(message)
      end

      @compatibility_bridge_warning_emitted = true
    end

    def self.official_backend_requires_native?
      Boxcars.configuration.openai_official_require_native
    end

    private_class_method :normalize_backend, :build_ruby_openai_client, :build_official_openai_client
    private_class_method :detect_official_client_class, :official_client_class?, :build_with_official_client_class
    private_class_method :ruby_openai_client_class?, :detect_ruby_openai_client_class, :ensure_ruby_openai_backend_compatible!
    private_class_method :build_with_ruby_openai_compat_class
    private_class_method :warn_official_backend_compatibility_bridge_once!
    private_class_method :official_backend_requires_native?
  end
end
