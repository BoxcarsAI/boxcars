# frozen_string_literal: true

RSpec.describe Boxcars::VectorStores::SplitText do
  subject(:output) { call_command }

  let(:arguments) do
    {
      separator: separator,
      chunk_size: chunk_size,
      chunk_overlap: chunk_overlap,
      text: text
    }
  end
  let(:separator) { ' ' }
  let(:chunk_size) { 7 }
  let(:chunk_overlap) { 3 }
  let(:text) { 'foo bar baz 123' }

  describe '#call' do
    it 'splits the text by character count' do
      expected_output = ['foo bar', 'bar baz', 'baz 123'].sort
      expect(output).to eq(expected_output)
    end

    context 'when the text is shorter than the chunk_size' do
      let(:chunk_size) { 2 }
      let(:chunk_overlap) { 0 }
      let(:text) { 'foo  bar' }

      it "doesn't create empty documents" do
        expect(output).to eq(%w[foo bar].sort)
      end
    end

    context 'with long words' do
      let(:chunk_size) { 3 }
      let(:chunk_overlap) { 1 }
      let(:text) { 'foo bar baz a a' }

      it 'splits by character count on long words' do
        expect(output).to eq(['foo', 'bar', 'baz', 'a a'].sort)
      end
    end

    context 'when shorter words are first' do
      let(:chunk_size) { 3 }
      let(:chunk_overlap) { 1 }
      let(:text) { 'a a foo bar baz' }

      it 'splits by character count when shorter words are first' do
        expect(output).to eq(['a a', 'foo', 'bar', 'baz'].sort)
      end
    end

    context 'when splits are not found easil' do
      let(:chunk_size) { 3 }
      let(:chunk_overlap) { 0 }
      let(:text) { 'foo bar baz 123' }

      it 'splits by characters when splits are not found easily' do
        expect(output).to eq(%w[foo bar baz 123].sort)
      end
    end

    context 'when chunk_overlap is greater than chunk_size' do
      let(:chunk_overlap) { 2 }
      let(:chunk_size) { 1 }

      it 'returns a failure' do
        expect { output }.to raise_error(Boxcars::ValueError)
      end
    end

    context 'when separator is not string' do
      let(:separator) { 2 }

      it 'returns a failure' do
        expect { output }.to raise_error(Boxcars::ValueError)
      end
    end

    context 'when chunk_size is not integer' do
      let(:chunk_size) { '2' }

      it 'returns a failure' do
        expect { output }.to raise_error(Boxcars::ValueError)
      end
    end

    context 'when chunk_overlap is not integer' do
      let(:chunk_overlap) { '2' }

      it 'returns a failure' do
        expect { output }.to raise_error(Boxcars::ValueError)
      end
    end

    context 'when text is not string' do
      let(:text) { :split_text }

      it 'returns a failure' do
        expect { output }.to raise_error(Boxcars::ValueError)
      end
    end

    def call_command
      described_class.call(**arguments)
    end
  end
end
