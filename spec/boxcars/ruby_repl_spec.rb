# frozen_string_literal: true

RSpec.describe Boxcars::RubyREPL do
  context "with RubyREPL" do
    repl = described_class.new
    it "prints" do
      expect(repl.run("puts 'hello'").to_answer).to eq("hello")
    end

    it "does math easy math" do
      expect(repl.run("puts 2 + 2").to_answer).to eq("4")
    end

    it "does math hard math" do
      expect(repl.run("puts Math.sqrt(16)").to_answer).to eq("4.0")
    end
  end
end
