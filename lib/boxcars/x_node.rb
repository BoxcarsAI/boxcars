# frozen_string_literal: true

module Boxcars
  class XNode
    attr_accessor :node, :children, :attributes

    def initialize(node)
      @node = node
      @valid_names = []
      @children = {}
      @attributes = node.attributes.values.to_h { |a| [a.name.to_sym, a.value] }

      node.children.each do |child|
        next if child.text?

        child_node = XNode.new(child)
        if @children[child.name].nil?
          @valid_names << child.name.to_sym
          @children[child.name] = child_node
        elsif @children[child.name].is_a?(Array)
          @children[child.name] << child_node
        else
          @children[child.name] = [@children[child.name], child_node]
        end
      end
    end

    def self.from_xml(xml)
      Boxcars::OptionalDependency.require!("nokogiri", feature: "XML trains and XML parsing helpers")
      xml = xml[xml.index("<")..-1] unless xml.start_with?("<")
      xml = xml[0..xml.rindex(">")] unless xml.end_with?(">")
      doc = Nokogiri::XML.parse(xml)
      if doc.errors.any?
        Boxcars.debug("XML: #{xml}", :yellow)
        # rubocop:disable Lint/Debugger
        debugger if ENV.fetch("DEBUG_XML", false)
        # rubocop:enable Lint/Debugger
        raise XmlError, "XML is not valid: #{doc.errors.map { |e| "#{e.line}:#{e.column} #{e.message}" }}"
      end
      XNode.new(doc.root)
    end

    def xml
      @node.to_xml
    end

    def text
      @node.text
    end

    def xpath(path)
      @node.xpath(path)
    end

    def xtext(path)
      # rubocop:disable Style/SafeNavigationChainLength
      rv = xpath(path)&.text&.gsub(/[[:space:]]+/, " ")&.strip
      # rubocop:enable Style/SafeNavigationChainLength
      return nil if rv.empty?

      rv
    end

    def stext
      @stext ||= text.gsub(/[[:space:]]+/, " ").strip # remove extra spaces
    end

    def [](key)
      @children[key.to_s]
    end

    def method_missing(name, *args)
      return @children[name.to_s] if @children.key?(name.to_s)

      super
    end

    def respond_to_missing?(method_name, include_private = false)
      @valid_names.include?(method_name.to_sym) || super
    end
  end
end
