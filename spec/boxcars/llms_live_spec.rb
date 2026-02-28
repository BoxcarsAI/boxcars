# frozen_string_literal: true

require "spec_helper"
require "timeout"

RSpec.describe "Live LLM smoke", :live_env do
  PROMPT = "Reply with exactly OK and nothing else.".freeze

  ENGINE_CASES = [
    {
      name: "openai",
      required_env: "OPENAI_ACCESS_TOKEN",
      run: lambda { |prompt|
        Boxcars::Openai.new(model: ENV.fetch("OPENAI_LIVE_MODEL", "gpt-4o-mini")).run(
          prompt,
          temperature: 0,
          max_tokens: 16
        )
      }
    },
    {
      name: "anthropic",
      required_env: "ANTHROPIC_API_KEY",
      run: lambda { |prompt|
        requested_model = ENV.fetch("ANTHROPIC_LIVE_MODEL", "").to_s.strip
        candidate_models = [
          requested_model,
          "claude-sonnet-4-20250514",
          "claude-3-7-sonnet-20250219",
          "claude-3-5-sonnet-20240620"
        ].reject(&:empty?).uniq

        last_error = nil
        candidate_models.each do |model_name|
          begin
            return Boxcars::Anthropic.new(model: model_name).run(
              prompt,
              temperature: 0,
              max_tokens: 32
            )
          rescue StandardError => e
            last_error = e
            next if e.message.to_s.match?(/model/i)

            raise
          end
        end

        raise(last_error || Boxcars::Error.new("Anthropic live smoke failed: no model candidates to try"))
      }
    },
    {
      name: "cohere",
      required_env: "COHERE_API_KEY",
      run: lambda { |prompt|
        Boxcars::Cohere.new(model: ENV.fetch("COHERE_LIVE_MODEL", "command-a-03-2025")).run(
          prompt,
          temperature: 0,
          max_tokens: 16
        )
      }
    },
    {
      name: "groq",
      required_env: "GROQ_API_KEY",
      run: lambda { |prompt|
        Boxcars::Groq.new(model: ENV.fetch("GROQ_LIVE_MODEL", "llama-3.3-70b-versatile")).run(
          prompt,
          temperature: 0,
          max_tokens: 16
        )
      }
    },
    {
      name: "gemini_ai",
      required_env: "GEMINI_API_KEY",
      run: lambda { |prompt|
        Boxcars::GeminiAi.new(model: ENV.fetch("GEMINI_LIVE_MODEL", "gemini-2.5-flash")).run(
          prompt,
          temperature: 0,
          max_tokens: 64
        )
      }
    },
    {
      name: "google",
      required_env: "GEMINI_API_KEY",
      run: lambda { |prompt|
        Boxcars::Google.new(model: ENV.fetch("GOOGLE_LIVE_MODEL", "gemini-2.5-flash")).run(
          prompt,
          temperature: 0,
          max_tokens: 64
        )
      }
    },
    {
      name: "perplexity_ai",
      required_env: "PERPLEXITY_API_KEY",
      run: lambda { |prompt|
        Boxcars::Perplexityai.new(model: ENV.fetch("PERPLEXITY_LIVE_MODEL", "sonar")).run(
          prompt,
          temperature: 0,
          max_tokens: 16
        )
      }
    },
    {
      name: "cerebras",
      required_env: "CEREBRAS_API_KEY",
      run: lambda { |prompt|
        Boxcars::Cerebras.new(model: ENV.fetch("CEREBRAS_LIVE_MODEL", "gpt-oss-120b")).run(
          prompt,
          temperature: 0,
          max_tokens: 64
        )
      }
    },
    {
      name: "together",
      required_env: "TOGETHER_API_KEY",
      timeout_seconds: 180,
      run: lambda { |prompt|
        Boxcars::Together.new(model: ENV.fetch("TOGETHER_LIVE_MODEL", "meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo")).run(
          prompt,
          temperature: 0,
          max_tokens: 16
        )
      }
    },
    {
      name: "ollama",
      optional_env: "OLLAMA_LIVE",
      run: lambda { |prompt|
        Boxcars::Ollama.new(model: ENV.fetch("OLLAMA_LIVE_MODEL", "llama3")).run(
          prompt,
          temperature: 0,
          max_tokens: 16
        )
      }
    },
    {
      name: "gpt4all",
      optional_env: "GPT4ALL_LIVE",
      enabled: lambda {
        defined?(::Gpt4all::ConversationalAI)
      },
      run: lambda { |prompt|
        Boxcars::Gpt4allEng.new(model_name: ENV.fetch("GPT4ALL_LIVE_MODEL", "gpt4all-j-v1.3-groovy")).run(prompt)
      }
    }
  ].freeze

  def truthy_env?(name)
    value = ENV.fetch(name, "").to_s.strip.downcase
    %w[1 true yes y on].include?(value)
  end

  def env_present?(name)
    !ENV.fetch(name, "").to_s.strip.empty?
  end

  def env_csv(name)
    ENV.fetch(name, "")
       .split(",")
       .map(&:strip)
       .reject(&:empty?)
  end

  before do
    skip "Set RUN_LIVE_LLM_SPECS=true to enable live provider calls" unless truthy_env?("RUN_LIVE_LLM_SPECS")

    Boxcars.configure do |config|
      config.log_prompts = false
      config.log_generated = false
    end
  end

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  it "exercises every configured LLM provider engine" do
    timeout_seconds = ENV.fetch("LLMS_LIVE_TIMEOUT_SECONDS", "120").to_i
    only_providers = env_csv("LLMS_LIVE_ONLY")
    skipped_providers = env_csv("LLMS_LIVE_SKIP")
    failures = []
    executed = []
    skipped = []

    ENGINE_CASES.each do |engine_case|
      provider_name = engine_case[:name]

      if only_providers.any? && !only_providers.include?(provider_name)
        skipped << "#{provider_name} (not in LLMS_LIVE_ONLY)"
        next
      end

      if skipped_providers.include?(provider_name)
        skipped << "#{provider_name} (in LLMS_LIVE_SKIP)"
        next
      end

      required_env = engine_case[:required_env]
      optional_env = engine_case[:optional_env]

      if required_env && !env_present?(required_env)
        skipped << "#{provider_name} (missing #{required_env})"
        next
      end

      if optional_env && !truthy_env?(optional_env)
        skipped << "#{provider_name} (set #{optional_env}=true to enable)"
        next
      end

      enabled = engine_case[:enabled]
      if enabled && !enabled.call
        skipped << "#{provider_name} (optional dependency not installed)"
        next
      end

      begin
        provider_timeout_seconds = ENV.fetch("#{provider_name.upcase}_LIVE_TIMEOUT_SECONDS",
                                             engine_case.fetch(:timeout_seconds, timeout_seconds).to_s).to_i
        output = nil
        VCR.turned_off do
          output = Timeout.timeout(provider_timeout_seconds) do
            engine_case.fetch(:run).call(PROMPT)
          end
        end

        executed << provider_name
        unless output.is_a?(String) && !output.strip.empty?
          failures << "#{provider_name} returned empty output: #{output.inspect}"
        end
      rescue StandardError => e
        failures << "#{provider_name} failed with #{e.class}: #{e.message}"
      end
    end

    puts "[llms-live] executed=#{executed.join(', ')}"
    puts "[llms-live] skipped=#{skipped.join(' | ')}" unless skipped.empty?

    expect(executed).not_to be_empty,
      "No live engines were configured. Provide API keys in .env and set RUN_LIVE_LLM_SPECS=true."
    expect(failures).to be_empty, "Live LLM failures:\n- #{failures.join("\n- ")}"
  end
end
