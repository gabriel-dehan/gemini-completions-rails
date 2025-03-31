module GeminiCompletions
  ##
  # Utility class that streams the completion of a conversation to the client
  # Allows for tool calls to be used
  #
  # @attr_reader [Gemini::Client] client The Gemini client
  # @attr_reader [ActionDispatch::Response] response The response object
  class Streamer
    attr_reader :client, :response, :text_buffer

    MAX_RECURSIVE_TOOL_CALLS = 10

    def initialize(client, response)
      @client = client
      @response = response
      @text_buffer = ""
    end

    ##
    # Streams the completion of a conversation
    #
    # @param contents [Array] The conversation history to send to the model
    # @param options [Hash] Additional options for the completion request
    # @option options [String] :systemInstruction The system instructions to use for the completion
    # @option options [Array] :tools A list of Gemini::Tool subclasses that should be available for the model to use
    # @param block [Proc] A callback to call when the completion is done
    #
    # @return [ActionDispatch::Response] The response object
    def stream_completion(contents = [], options = {})
      raise Gemini::Error, "Stream completion requires contents" if contents.empty?

      # Streaming headers
      response.headers['Content-Type'] = 'text/event-stream'
      response.headers['Cache-Control'] = 'no-cache'
      response.headers['Connection'] = 'keep-alive'

      # I clearly have written too much typescript these past few years x)
      complete_event_data = ->() { { status: 'done' }.to_json }
      error_event_data = ->(error) { { status: 'error', error: error.message }.to_json }

      begin
        generate_completion(contents, response, options)

        # Callback after generation is complete
        if block_given?
          yield self, @text_buffer
        end

        write_to_stream(event: "complete", data: complete_event_data.call)
      rescue => e
        write_to_stream(event: "error", data: error_event_data.call(e))
      ensure
        response.stream.close
      end
    end

    def write_to_stream(data: nil, event: nil)
      response.stream.write("data: #{data}\n\n") if data
      response.stream.write("event: #{event}\n\n") if event
    end

    private

      ##
      # Recursively generates completions, handling tool calls as needed
      #
      # @param contents [Array] Current conversation history
      # @param response [ActionDispatch::Response] The response object
      # @param options [Hash] Additional options for the completion request
      # @param multi_turn_tool_usage_count [Integer] Number of recursive tool call rounds so far
      #
      # @return [ActionDispatch::Response] The response object
      def generate_completion(contents, response, options, multi_turn_tool_usage_count = 0)
        enforce_max_tool_uses(multi_turn_tool_usage_count)

        # We buffer responses with tool calls to ensure we have all parts before processing
        # This is needed because a single function call might span multiple chunks
        buffered_response_with_tools = []
        # Call the Gemini API and handle the streamed chunks
        client.generate_content(contents, options) do |chunk, uses_tools|
          if uses_tools
            buffered_response_with_tools << chunk
          else
            write_to_stream(data: chunk.to_json)
            @text_buffer << extract_text_from_chunk(chunk)
          end
        end

        # If we have any tool calls, process them
        if buffered_response_with_tools.any?
          process_tools_calls(contents, buffered_response_with_tools, options, multi_turn_tool_usage_count)
        end

        response
      end

      ##
      # Processes collected response chunks that contain tool calls
      #
      # @param contents [Array] Current conversation history
      # @param buffered_response_with_tools [Array] Chunks containing tool calls and text parts
      # @param options [Hash] Additional options for the completion request
      # @param multi_turn_tool_usage_count [Integer] Current tool call depth
      #
      # @return [ActionDispatch::Response] The response object
      def process_tools_calls(contents, buffered_response_with_tools, options, multi_turn_tool_usage_count)
        last_chunk = buffered_response_with_tools.last

        # Flatten all parts from all chunks and put them in the last chunk
        # We use the last chunk because it contains the actual token count and more relevant information
        # (Maybe a bit dirty, but it's just easier to handle)
        last_chunk["candidates"][0]["content"]["parts"] = buffered_response_with_tools.map do |chunk|
          chunk.dig("candidates", 0, "content", "parts")
        end.flatten

        # Call the tools and get the responses
        tool_call_responses = call_tools(last_chunk)

        # Once we have the tool call responses, we have to send them to the LLM once more
        if tool_call_responses.length > 0
          # Stream the model response with included function calls for front-end to display if necessary
          write_to_stream(data: last_chunk.to_json)
          write_to_stream(event: "executed_tools")
          @text_buffer << extract_text_from_chunk(last_chunk)

          # Save the model response (with function calls) to add to conversation history
          model_response = {
            role: "model",
            parts: last_chunk["candidates"][0]["content"]["parts"]
          }

          updated_contents = contents + [model_response] + tool_call_responses
          # Recursively call with updated conversation

          return generate_completion(updated_contents, response, options, multi_turn_tool_usage_count + 1)
        else
          # If no tool were used, stream the response directly
          write_to_stream(data: last_chunk.to_json)
          @text_buffer << extract_text_from_chunk(last_chunk)

          response
        end
      end

      ##
      # Processes all function calls in a response
      #
      # @param chunk [Hash] A single, consolidated chunk containing all the parts with tool calls
      #
      # @return [Array] Array of function response objects
      def call_tools(chunk)
        tool_call_responses = []

        chunk["candidates"][0]["content"]["parts"].each do |part|
          if part["functionCall"]
            tool_call_responses << execute_tool_call(part["functionCall"])
          end
        end

        tool_call_responses
      end

      ##
      # Executes a single tool call
      #
      # @param function_call_data [Hash] Function call data (part["functionCall"])
      #
      # @return [Hash] Formatted function response for the conversation history
      def execute_tool_call(function_call_data)
        tool_name = function_call_data["name"]
        tool_args = function_call_data["args"]

        tool = Gemini::Tool.find_by_name(tool_name)

        begin
          result = tool.call(tool_args)
        rescue => e
          result = { "error": e.message }
          write_to_stream(data: e.message, event: "tool_error")
        end

        # Return the function response to be added to the conversation history
        {
          role: "user",
          parts: [{
            functionResponse: {
              name: tool_name,
              response: {
                result: result
              }
            }
          }]
        }
      end

      ##
      # Prevents infinite loops of tool calls
      #
      # @param tool_calls_count [Integer] Current count of tool call rounds
      # @raise [Gemini::Error] When maximum tool calls is exceeded
      def enforce_max_tool_uses(tool_calls_count)
        if tool_calls_count >= MAX_RECURSIVE_TOOL_CALLS
          error_message = "Maximum number of tool calls reached (#{MAX_RECURSIVE_TOOL_CALLS})"
          write_to_stream(data: error_message, event: "error")
          raise Gemini::Error, error_message
        end
      end

      ##
      # Extracts the text from a chunk's parts
      #
      # @param chunk [Hash] A single chunk
      #
      # @return [String] The merged text from all parts
      def extract_text_from_chunk(chunk)
        parts = chunk.dig("candidates", 0, "content", "parts")
        parts.select { |part| part["text"] }.map { |part| part["text"] }.join if parts.any?
      end
  end
end