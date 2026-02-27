# frozen_string_literal: true

require "json"
require "open3"
require "timeout"

module Boxcars
  module MCP
    # Minimal MCP stdio client using JSON-RPC framing (`Content-Length` headers).
    # It supports the core handshake plus tool discovery and invocation.
    class StdioClient < Client
      DEFAULT_PROTOCOL_VERSION = "2024-11-05"

      attr_reader :command, :args, :cwd, :env, :process_wait_thread, :server_info, :server_capabilities

      def initialize(command:, args: [], cwd: nil, env: {}, auto_initialize: true,
                     client_name: "boxcars", client_version: Boxcars::VERSION,
                     protocol_version: DEFAULT_PROTOCOL_VERSION, initialization_timeout: 10)
        @command = command
        @args = Array(args)
        @cwd = cwd
        @env = env || {}
        @auto_initialize = auto_initialize
        @client_name = client_name
        @client_version = client_version
        @protocol_version = protocol_version
        @initialization_timeout = initialization_timeout

        @stdin = nil
        @stdout = nil
        @stderr = nil
        @process_wait_thread = nil
        @stderr_thread = nil
        @stderr_buffer = +""
        @request_id = 0
        @pending_notifications = []
        @initialized = false
        @server_info = nil
        @server_capabilities = nil
      end

      def connect!
        return self if connected?

        popen_process!
        initialize_session! if @auto_initialize
        self
      end

      def connected?
        !@stdin.nil? && !@stdout.nil? && @process_wait_thread&.alive?
      end

      def initialize_session!
        connect_without_initialize! unless connected?
        return self if @initialized

        response = with_timeout(@initialization_timeout) do
          request("initialize", {
                    protocolVersion: @protocol_version,
                    capabilities: {},
                    clientInfo: {
                      name: @client_name,
                      version: @client_version
                    }
                  })
        end

        result = response["result"] || {}
        @server_info = result["serverInfo"] || result[:serverInfo]
        @server_capabilities = result["capabilities"] || result[:capabilities] || {}
        notify("notifications/initialized", {})
        @initialized = true
        self
      end

      def list_tools
        ensure_initialized!
        response = request("tools/list", {})
        result = response["result"] || {}
        result["tools"] || result[:tools] || []
      end

      def call_tool(name:, arguments:)
        ensure_initialized!
        response = request("tools/call", { name:, arguments: arguments || {} })
        response["result"] || response[:result] || {}
      end

      def close
        @stdin&.close unless @stdin&.closed?
        @stdout&.close unless @stdout&.closed?
        @stderr&.close unless @stderr&.closed?
        @stderr_thread&.kill
        @process_wait_thread&.kill if @process_wait_thread&.alive?
      ensure
        @stdin = @stdout = @stderr = @process_wait_thread = @stderr_thread = nil
      end

      private

      def connect_without_initialize!
        return if connected?

        popen_process!
      end

      def popen_process!
        popen_options = {}
        popen_options[:chdir] = cwd if cwd
        stdin, stdout, stderr, wait_thr = Open3.popen3(env, command, *args, **popen_options)
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @process_wait_thread = wait_thr
        @stdin.sync = true
        @stdout.sync = true if @stdout.respond_to?(:sync=)
        start_stderr_collector!
      rescue Errno::ENOENT => e
        raise Boxcars::ConfigurationError, "MCP command not found: #{command} (#{e.message})"
      end

      def start_stderr_collector!
        return unless @stderr

        @stderr_thread = Thread.new do
          begin
            while (line = @stderr.gets)
              @stderr_buffer << line
            end
          rescue StandardError
            nil
          end
        end
      end

      def ensure_initialized!
        connect! unless connected?
        initialize_session! unless @initialized
      end

      def request(method, params)
        id = next_request_id
        write_message(
          {
            jsonrpc: "2.0",
            id: id,
            method: method,
            params: params
          }
        )
        read_response_for(id)
      end

      def notify(method, params = {})
        write_message(
          {
            jsonrpc: "2.0",
            method: method,
            params: params
          }
        )
        nil
      end

      def next_request_id
        @request_id += 1
      end

      def write_message(payload)
        ensure_process_alive!
        json = JSON.generate(payload)
        bytes = json.bytesize
        @stdin.write("Content-Length: #{bytes}\r\n\r\n")
        @stdin.write(json)
        @stdin.flush
      rescue IOError, Errno::EPIPE => e
        raise Boxcars::Error, "MCP stdio write failed: #{e.message}#{stderr_suffix}"
      end

      def read_response_for(request_id)
        loop do
          msg = read_message
          if msg.key?("id") && msg["id"] == request_id
            if msg.key?("error") && msg["error"]
              raise Boxcars::Error, "MCP error for request #{request_id}: #{msg['error'].inspect}"
            end
            return msg
          end

          @pending_notifications << msg
        end
      end

      def read_message
        ensure_process_alive!
        headers = read_headers
        content_length = headers["content-length"]&.to_i
        raise Boxcars::Error, "MCP message missing Content-Length header" unless content_length && content_length >= 0

        body = @stdout.read(content_length)
        raise Boxcars::Error, "MCP stdio stream closed while reading message body#{stderr_suffix}" if body.nil? || body.bytesize != content_length

        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Boxcars::Error, "Invalid MCP JSON payload: #{e.message}#{stderr_suffix}"
      rescue IOError => e
        raise Boxcars::Error, "MCP stdio read failed: #{e.message}#{stderr_suffix}"
      end

      def read_headers
        headers = {}

        loop do
          line = @stdout.gets
          raise Boxcars::Error, "MCP stdio stream closed while reading headers#{stderr_suffix}" if line.nil?

          stripped = line.strip
          break if stripped.empty?

          key, value = stripped.split(":", 2)
          next unless key && value

          headers[key.downcase] = value.strip
        end

        headers
      end

      def ensure_process_alive!
        return if @process_wait_thread&.alive?

        status = @process_wait_thread&.value
        code = status&.exitstatus
        raise Boxcars::Error, "MCP process exited#{code ? " (#{code})" : ''}#{stderr_suffix}"
      end

      def with_timeout(seconds)
        return yield if seconds.nil?

        Timeout.timeout(seconds) { yield }
      rescue Timeout::Error
        raise Boxcars::Error, "MCP request timed out after #{seconds}s#{stderr_suffix}"
      end

      def stderr_suffix
        return "" if @stderr_buffer.nil? || @stderr_buffer.strip.empty?

        " | stderr: #{@stderr_buffer.strip.lines.last(3).join(' ').strip}"
      end
    end
  end
end
