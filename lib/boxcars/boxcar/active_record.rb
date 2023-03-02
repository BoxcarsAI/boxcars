# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers
  class ActiveRecord < EngineBoxcar
    # the description of this engine boxcar
    ARDESC = "useful for when you need to query a database for an application named %<name>s."
    LOCKED_OUT_MODELS = %w[ActiveRecord::SchemaMigration ActiveRecord::InternalMetadata ApplicationRecord].freeze
    attr_accessor :connection, :requested_models, :read_only, :approval_callback
    attr_reader :except_models

    # @param engine [Boxcars::Engine] The engine to user for this boxcar. Can be inherited from a train if nil.
    # @param models [Array<ActiveRecord::Model>] The models to use for this boxcar. Will use all if nil.
    # @param read_only [Boolean] Whether to use read only models. Defaults to true unless you pass an approval function.
    # @param approval_callback [Proc] A function to call to approve changes. Defaults to nil.
    # @param kwargs [Hash] Any other keyword arguments. These can include:
    #   :name, :description, :prompt, :except_models, :top_k, and :stop
    def initialize(engine: nil, models: nil, read_only: nil, approval_callback: nil, **kwargs)
      check_models(models)
      @except_models = LOCKED_OUT_MODELS + kwargs[:except_models].to_a
      @approval_callback = approval_callback
      @read_only = read_only.nil? ? !approval_callback : read_only
      the_prompt = kwargs[prompt] || my_prompt
      name = kwargs[:name] || "Data"
      kwargs[:stop] ||= ["Answer:"]
      super(name: name,
            description: kwargs[:description] || format(ARDESC, name: name),
            engine: engine,
            prompt: the_prompt,
            **kwargs)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional
      { model_info: model_info }.merge super
    end

    private

    def read_only?
      read_only
    end

    def check_models(models)
      if models.is_a?(Array) && models.length.positive?
        @requested_models = models
        models.each do |m|
          raise ArgumentError, "model #{m} needs to be an Active Record model" unless m.ancestors.include?(::ActiveRecord::Base)
        end
      elsif models
        raise ArgumentError, "models needs to be an array of Active Record models"
      end
    end

    def wanted_models
      the_models = requested_models || ::ActiveRecord::Base.descendants
      the_models.reject { |m| except_models.include?(m.name) }
    end

    def models
      models = wanted_models.map(&:name)
      models.join(", ")
    end

    def model_info
      models = wanted_models
      models.inspect
    end

    # to be safe, we wrap the code in a transaction and rollback
    def rollback_after_running
      rv = nil
      ::ActiveRecord::Base.transaction do
        rv = yield
      ensure
        raise ::ActiveRecord::Rollback
      end
      rv
    end

    # check for dangerous code that is outside of ActiveRecord
    def safe_to_run?(code)
      bad_words = %w[commit drop_constraint drop_constraint! drop_extension drop_extension! drop_foreign_key drop_foreign_key! \
                     drop_index drop_index! drop_join_table drop_join_table! drop_materialized_view drop_materialized_view! \
                     drop_partition drop_partition! drop_schema drop_schema! drop_table drop_table! drop_trigger drop_trigger! \
                     drop_view drop_view! eval execute reset revoke rollback truncate].freeze
      without_strings = code.gsub(/('([^'\\]*(\\.[^'\\]*)*)'|"([^"\\]*(\\.[^"\\]*)*"))/, 'XX')
      word_list = without_strings.split(/[.,()]/)

      bad_words.each do |w|
        if word_list.include?(w)
          Boxcars.info "code included destructive instruction: #{w} #{code}", :red
          return false
        end
      end

      true
    end

    def evaluate_input(code)
      raise SecurityError, "Found unsafe code while evaluating: #{code}" unless safe_to_run?(code)

      # rubocop:disable Security/Eval
      eval code
      # rubocop:enable Security/Eval
    end

    def change_count(changes_code)
      return 0 unless changes_code

      rollback_after_running do
        Boxcars.debug "computing change count with: #{changes_code}", :yellow
        evaluate_input changes_code
      end
    end

    def approved?(changes_code, code)
      # find out how many changes there are
      changes = change_count(changes_code)
      return true unless changes&.positive?

      Boxcars.debug "Pending Changes: #{changes}", :yellow, style: :bold
      change_str = "#{changes} change#{'s' if changes.to_i > 1}"
      raise SecurityError, "Can not run code that makes #{change_str} in read-only mode" if read_only?

      return approval_callback.call(changes, code) if approval_callback.is_a?(Proc)

      true
    end

    def run_active_record_code(code)
      Boxcars.debug code, :yellow
      if read_only?
        rollback_after_running do
          evaluate_input code
        end
      else
        evaluate_input code
      end
    end

    def get_active_record_answer(text)
      code = text[/^ARCode: (.*)/, 1]
      changes_code = text[/^ARChanges: (.*)/, 1]
      raise SecurityError, "Permission to run code that makes changes denied" unless approved?(changes_code, code)

      output = run_active_record_code(code)
      output = 0 if output.is_a?(Array) && output.empty?
      output = output.first if output.is_a?(Array) && output.length == 1
      output = output[output.keys.first] if output.is_a?(Hash) && output.length == 1
      "Answer: #{output.to_json}"
    rescue StandardError => e
      "Error: #{e.message}"
    end

    def get_answer(text)
      case text
      when /^ARCode:/
        get_active_record_answer(text)
      when /^Answer:/
        text
      else
        raise Boxcars::Error "Unknown format from engine: #{text}"
      end
    end

    TEMPLATE = <<~IPT
      Given an input question, first create a syntactically correct Rails Active Record code to run,
      then look at the results of the code and return the answer. Unless the user specifies
      in her question a specific number of examples she wishes to obtain, limit your code
      to at most %<top_k>s results.

      Never query for all the columns from a specific model, only ask for a the few relevant attributes given the question.

      Pay attention to use only the attribute names that you can see in the model description. Be careful to not query for attributes that do not exist.
      Also, pay attention to which attribute is in which model.

      Use the following format:
      Question: "Question here"
      ARCode: "Active Record code to run"
      ARChanges: "Active Record code to compute the number of records going to change" - Only add this line if the ARCode on the line before will make data changes
      Answer: "Final answer here"

      Only use the following Active Record models:
      %<model_info>s

      Question: %<question>s
    IPT

    # The prompt to use for the engine.
    def my_prompt
      @my_prompt ||= Prompt.new(input_variables: [:question], other_inputs: [:top_k], output_variables: [:answer],
                                template: TEMPLATE)
    end
  end
end
