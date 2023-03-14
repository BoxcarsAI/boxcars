# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers
  class ActiveRecord < EngineBoxcar
    # the description of this engine boxcar
    ARDESC = "useful for when you need to query a database for an application named %<name>s."
    LOCKED_OUT_MODELS = %w[ActiveRecord::SchemaMigration ActiveRecord::InternalMetadata ApplicationRecord].freeze
    attr_accessor :connection, :requested_models, :read_only, :approval_callback, :code_only
    attr_reader :except_models

    # @param models [Array<ActiveRecord::Model>] The models to use for this boxcar. Will use all if nil.
    # @param except_models [Array<ActiveRecord::Model>] The models to exclude from this boxcar. Will exclude none if nil.
    # @param read_only [Boolean] Whether to use read only models. Defaults to true unless you pass an approval function.
    # @param approval_callback [Proc] A function to call to approve changes. Defaults to nil.
    # @param kwargs [Hash] Any other keyword arguments. These can include:
    #   :name, :description, :prompt, :except_models, :top_k, :stop, :code_only and :engine
    def initialize(models: nil, except_models: nil, read_only: nil, approval_callback: nil, **kwargs)
      check_models(models, except_models)
      @approval_callback = approval_callback
      @read_only = read_only.nil? ? !approval_callback : read_only
      @code_only = kwargs.delete(:code_only) || false
      kwargs[:name] ||= "Data"
      kwargs[:description] ||= format(ARDESC, name: name)
      kwargs[:prompt] ||= my_prompt
      super(**kwargs)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional
      { model_info: model_info }.merge super
    end

    private

    def read_only?
      read_only
    end

    def code_only?
      code_only
    end

    def check_models(models, exceptions)
      if models.is_a?(Array) && models.length.positive?
        @requested_models = models
        models.each do |m|
          raise ArgumentError, "model #{m} needs to be an Active Record model" unless m.ancestors.include?(::ActiveRecord::Base)
        end
      elsif models
        raise ArgumentError, "models needs to be an array of Active Record models"
      end
      @except_models = LOCKED_OUT_MODELS + exceptions.to_a
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

      Boxcars.debug "#{name}(Pending Changes): #{changes}", :yellow
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

    def clean_up_output(output)
      output = output.as_json if output.is_a?(::ActiveRecord::Result)
      output = 0 if output.is_a?(Array) && output.empty?
      output = output.first if output.is_a?(Array) && output.length == 1
      output = output[output.keys.first] if output.is_a?(Hash) && output.length == 1
      output = output.as_json if output.is_a?(::ActiveRecord::Relation)
      output
    end

    def get_active_record_answer(text)
      code = text[/^ARCode: (.*)/, 1]
      changes_code = text[/^ARChanges: (.*)/, 1]
      return Result.new(status: :ok, explanation: "code to run", code: code, changes_code: changes_code) if code_only?

      raise SecurityError, "Permission to run code that makes changes denied" unless approved?(changes_code, code)

      output = clean_up_output(run_active_record_code(code))
      Result.new(status: :ok, answer: output, explanation: "Answer: #{output.to_json}", code: code)
    rescue StandardError => e
      Result.new(status: :error, answer: nil, explanation: "Error: #{e.message}", code: code)
    end

    def get_answer(text)
      case text
      when /^ARCode:/
        get_active_record_answer(text)
      when /^Answer:/
        Result.from_text(text)
      else
        Result.from_error("Unknown format from engine: #{text}")
      end
    end

    CTEMPLATE = [
      syst("Given an input question, first create a syntactically correct Rails Active Record code to run, ",
           "then look at the results of the code and return the answer. Unless the user specifies ",
           "in her question a specific number of examples she wishes to obtain, limit your code ",
           "to at most %<top_k>s results.\n",
           "Never query for all the columns from a specific model, ",
           "only ask for the relevant attributes given the question.\n",
           "Pay attention to use only the attribute names that you can see in the model description. ",
           "Be careful to not query for attributes that do not exist.\n",
           "Also, pay attention to which attribute is in which model."),
      syst("Use the following format:\n",
           "Question: 'Question here'\n",
           "ARCode: 'Active Record code to run'\n",
           "ARChanges: 'Active Record code to compute the number of records going to change' - ",
           "Only add this line if the ARCode on the line before will make data changes.\n",
           "Answer: 'Final answer here'"),
      syst("Only use the following Active Record models: %<model_info>s"),
      assi("Question: %<question>s")
    ].freeze

    # The prompt to use for the engine.
    def my_prompt
      @conversation ||= Conversation.new(lines: CTEMPLATE)
      @my_prompt ||= ConversationPrompt.new(
        conversation: @conversation,
        input_variables: [:question],
        other_inputs: [:top_k],
        output_variables: [:answer])
    end
  end
end
