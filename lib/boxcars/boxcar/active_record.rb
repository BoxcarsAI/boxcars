# frozen_string_literal: true

# Boxcars is a framework for running a series of tools to get an answer to a question.
module Boxcars
  # A Boxcar that interprets a prompt and executes SQL code to get answers
  # rubocop:disable Metrics/ClassLength
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
      kwargs[:name] ||= get_name
      kwargs[:description] ||= format(ARDESC, name: name)
      kwargs[:prompt] ||= my_prompt
      super(**kwargs)
    end

    # @return Hash The additional variables for this boxcar.
    def prediction_additional(_inputs)
      { model_info: model_info }.merge super
    end

    private

    def get_name
      return Rails.application.class.module_parent.name if defined?(Rails)
    rescue StandardError => e
      boxcars.error "Error getting rails name application name: #{e.message}"
      nil
    end

    def read_only?
      read_only
    end

    def code_only?
      code_only
    end

    def check_models(models, exceptions)
      if models.is_a?(Array) && models.length.positive?
        models.map { |m| m.is_a?(Class) ? m : m.constantize }
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
      result = nil
      runtime_exception = nil
      ::ActiveRecord::Base.transaction do
        begin
          result = yield
        rescue SecurityError, ::NameError, ::Error => e
          Boxcars.error("Error while running code: #{e.message[0..60]} ...", :red)
          runtime_exception = e
        end
      ensure
        raise ::ActiveRecord::Rollback
      end
      raise runtime_exception if runtime_exception

      result
    end

    # check for dangerous code that is outside of ActiveRecord
    def safe_to_run?(code)
      bad_words = %w[commit drop_constraint drop_constraint! drop_extension drop_extension! drop_foreign_key drop_foreign_key! \
                     drop_index drop_index! drop_join_table drop_join_table! drop_materialized_view drop_materialized_view! \
                     drop_partition drop_partition! drop_schema drop_schema! drop_table drop_table! drop_trigger drop_trigger! \
                     drop_view drop_view! eval instance_eval send system execute reset revoke rollback truncate \
                     encrypted_password].freeze
      without_strings = code.gsub(/('([^'\\]*(\\.[^'\\]*)*)'|"([^"\\]*(\\.[^"\\]*)*"))/, 'XX')

      if without_strings.include?("`")
        Boxcars.info "code included possibly destructive backticks #{code}", :red
        return false
      end

      word_list = without_strings.split(/[.,() :\[\]]/)

      bad_words.each do |w|
        if word_list.include?(w)
          Boxcars.info "code included possibly destructive instruction: '#{w}' in #{code}", :red
          return false
        end
      end

      true
    end

    # run the code in a safe environment
    # @param code [String] The code to run
    # @return [Object] The result of the code
    def eval_safe_wrapper(code)
      # if the code used ActiveRecord, we need to add :: in front of it to escape the module
      new_code = code.gsub(/\b(ActiveRecord::)/, '::\1')

      # sometimes the code will have a puts or print in it, which will miss. Remove them.
      new_code = new_code.gsub(/\b(puts|print)\b/, '')
      proc do
        $SAFE = 4
        # rubocop:disable Security/Eval
        eval new_code
        # rubocop:enable Security/Eval
      end.call
    end

    def evaluate_input(code)
      raise SecurityError, "Found unsafe code while evaluating: #{code}" unless safe_to_run?(code)

      eval_safe_wrapper code
    end

    def change_count(changes_code)
      return 0 if changes_code.nil? || changes_code.empty? || changes_code =~ %r{^(None|N/A)$}i

      rollback_after_running do
        Boxcars.debug "computing change count with: #{changes_code}", :yellow
        evaluate_input changes_code
      end
    end

    def approved?(changes_code, code)
      # find out how many changes there are
      changes = change_count(changes_code)
      begin
        return true unless changes&.positive?
      rescue StandardError => e
        Boxcars.error "Error while computing change count: #{e.message}", :red
      end

      Boxcars.debug "#{name}(Pending Changes): #{changes}", :yellow
      if read_only?
        change_str = "#{changes} change#{'s' if changes.to_i > 1}"
        Boxcars.error("Can not run code that makes #{change_str} in read-only mode", :red)
        return false
      end

      return approval_callback.call(changes, code) if approval_callback.is_a?(Proc)

      true
    end

    def run_active_record_code(code)
      code = ::Regexp.last_match(1) if code =~ /`(.+)`/
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

    def error_message(err, stage)
      msg = err.message
      msg = ::Regexp.last_match(1) if msg =~ /^(.+)' for #<Boxcars::ActiveRecord/
      msg.gsub!(/Boxcars::ActiveRecord::/, '')
      "For the value you gave for #{stage}, fix this error: #{msg}"
    end

    def get_active_record_answer(text)
      changes_code = extract_code text.split('ARCode:').first.split('ARChanges:').last.strip if text =~ /^ARChanges:/
      code = extract_code text.split('ARCode:').last.strip
      return Result.new(status: :ok, explanation: "code to run", code: code, changes_code: changes_code) if code_only?

      have_approval = false
      begin
        have_approval = approved?(changes_code, code)
      rescue NameError, Error => e
        return Result.new(status: :error, explanation: error_message(e, "ARChanges"), changes_code: changes_code)
      end

      raise SecurityError, "Permission to run code that makes changes denied" unless have_approval

      begin
        output = clean_up_output(run_active_record_code(code))
        Result.new(status: :ok, answer: output, explanation: "Answer: #{output.to_json}", code: code)
      rescue SecurityError => e
        raise e
      rescue ::StandardError => e
        Result.new(status: :error, answer: nil, explanation: error_message(e, "ARCode"), code: code)
      end
    end

    def get_answer(text)
      case text
      when /^ARCode:/
        get_active_record_answer(text)
      when /^Answer:/
        Result.from_text(text)
      else
        Result.from_error("Error: Your answer wasn't formatted properly - try again. I expected your answer to " \
                          "start with \"ARChanges:\" or \"ARCode:\"")
      end
    end

    CTEMPLATE = [
      syst("You are a Ruby on Rails Active Record code generator"),
      syst("Given an input question, first create a syntactically correct Rails Active Record code to run, ",
           "then look at the results of the code and return the answer. Unless the user specifies ",
           "in her question a specific number of examples she wishes to obtain, limit your code ",
           "to at most %<top_k>s results.\n",
           "Never query for all the columns from a specific model, ",
           "only ask for the relevant attributes given the question.\n",
           "Also, pay attention to which attribute is in which model.\n\n",
           "Use the following format:\n",
           "Question: ${{Question here}}\n",
           "ARChanges: ${{Active Record code to compute the number of records going to change}} - ",
           "Only add this line if the ARCode on the next line will make data changes.\n",
           "ARCode: ${{Active Record code to run}} - make sure you use valid code\n",
           "Answer: ${{Final answer here}}\n\n",
           "Only use the following Active Record models: %<model_info>s\n",
           "Pay attention to use only the attribute names that you can see in the model description.\n",
           "Do not make up variable or attribute names, and do not share variables between the code in ARChanges and ARCode\n",
           "Be careful to not query for attributes that do not exist, and to use the format specified above.\n",
           "Finally, try not to use print or puts in your code"
          ),
      user("Question: %<question>s")
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
  # rubocop:enable Metrics/ClassLength
end
