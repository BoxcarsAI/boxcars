# frozen_string_literal: true

module Boxcars
  module VectorStore
    # Split a text into chunks of a given size.
    class SplitText
      include VectorStore

      # @param separator [String] The string to use to split the text.
      # @param chunk_size [Integer] The size of each chunk.
      # @param chunk_overlap [Integer] The amount of overlap between chunks.
      # @param text [String] The text to split.
      def initialize(separator: "Search", chunk_size: 7, chunk_overlap: 3, text: "")
        # require 'debugger'; debugger
        validate_params(separator, chunk_size, chunk_overlap, text)

        @separator = separator
        @chunk_size = chunk_size
        @chunk_overlap = chunk_overlap
        @text = text
      end

      def call
        splits = text.split(separator)
        merged_splits = merge_splits(splits, separator)

        merged_splits&.sort
      end

      private

      attr_reader :separator, :chunk_size, :chunk_overlap, :text

      def validate_params(separator, chunk_size, chunk_overlap, text)
        raise_error("separator must be a string") unless separator.is_a?(String)
        raise_error("chunk_size must be an integer") unless chunk_size.is_a?(Integer)
        raise_error("chunk_overlap must be an integer") unless chunk_overlap.is_a?(Integer)
        raise_error("text must be a string") unless text.is_a?(String)
        raise_error("chunk_overlap must be less than chunk_size") if chunk_overlap >= chunk_size
      end

      def raise_error(message)
        raise ::Boxcars::ValueError, message
      end

      def merge_splits(splits, separator)
        merged_splits = []
        current_doc = []
        total = 0

        splits.each do |split|
          split_len = split.length
          total = process_split(total, split_len, current_doc, merged_splits, separator)
          current_doc << split
          total += split_len
        end

        add_remaining_doc(current_doc, merged_splits, separator)
        merged_splits
      end

      def process_split(total, split_len, current_doc, merged_splits, separator)
        if total + split_len >= chunk_size
          warn_if_chunk_too_large(total)
          total = handle_large_chunk(total, split_len, current_doc, merged_splits, separator)
        end
        total
      end

      def warn_if_chunk_too_large(total)
        return unless total > chunk_size

        puts "Created a chunk of size #{total}, which is longer than the specified #{chunk_size}"
      end

      def handle_large_chunk(total, split_len, current_doc, merged_splits, separator)
        if current_doc.length.positive?
          doc = join_docs(current_doc, separator)
          merged_splits << doc if doc
          total = remove_overlap(total, split_len, current_doc)
        end
        total
      end

      def remove_overlap(total, split_len, current_doc)
        while total > chunk_overlap || (total + split_len > chunk_size && total.positive?)
          total -= current_doc[0].length
          current_doc.shift
        end
        total
      end

      def add_remaining_doc(current_doc, merged_splits, separator)
        doc = join_docs(current_doc, separator)
        merged_splits << doc if doc
      end

      def join_docs(docs, separator)
        text = docs.join(separator).strip
        text.empty? ? nil : text
      end
    end
  end
end
