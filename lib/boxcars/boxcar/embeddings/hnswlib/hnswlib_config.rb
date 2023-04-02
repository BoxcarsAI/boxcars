# frozen_string_literal: true

module Boxcars
  module Embeddings
    module Hnswlib
      class HnswlibConfig
        attr_reader :metric, :max_item, :dim, :ef_construction, :m

        # used for search index.
        #
        # @param max_item [Integer] The maximum number of items.
        #
        # @param metric [String] The distance metric between vectors ('l2', 'dot', or 'cosine').
        #
        # @param ef_construction [Integer] The size of the dynamic list for the nearest neighbors.
        #                        It controls the index time/accuracy trade-off.
        #
        # @param max_outgoing_connection [Integer] The maximum number of outgoing connections in the graph
        #
        # reference: https://yoshoku.github.io/hnswlib.rb/doc/
        def initialize(
          metric: "l2",
          max_item: 10000,
          dim: 2,
          ef_construction: 200,
          max_outgoing_connection: 16
        )
          @metric = metric
          @max_item = max_item
          @dim = dim
          @ef_construction = ef_construction
          @max_outgoing_connection = max_outgoing_connection
        end

        def space
          @metric == 'dot' ? 'ip' : 'l2'
        end
      end
    end
  end
end
