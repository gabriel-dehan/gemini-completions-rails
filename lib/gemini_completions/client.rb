module GeminiCompletions
  class Client
    BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

    ##
    # Creates a new Gemini client with the given API key and options
    #
    # @param api_key [String] Gemini API key
    # @param options [Hash] Model options (defaults: { model: "gemini-2.0-flash", stream: false })
    # @option options [String] :model The model to use (default: "gemini-2.0-flash")
    # @option options [Boolean] :stream Whether to stream the response (default: false)
    # @raise [ArgumentError] if api_key or model is not provided
    #
    def initialize(api_key = nil, options = { model: "gemini-2.0-flash", stream: false })
      @api_key = api_key
      raise ArgumentError, "Gemini API key is required" unless @api_key

      @model = options[:model]
      raise ArgumentError, "Model is required" unless @model

      @stream = options[:stream] || false
    end

    ##
    # Generates content from a conversation array. Example:
    #
    # @example
    #   client.generate_content([
    #     { role: "user", parts: [{ text: "Hello!" }] },
    #     { role: "model", parts: [{ text: "Hi there!" }] },
    #     { role: "user", parts: [{ text: "How are you?" }] }
    #   ], temperature: 0.7)
    #
    # @param contents [Array<Hash>] Array of message objects in the following format:
    #   [
    #     {
    #       role: "user"|"model",
    #       parts: [
    #         {
    #           text: String
    #         }
    #       ]
    #     }
    #   ]
    # @param options [Hash] Additional generation options
    # option options [String] System instructions
    # @option options [Float] :temperature (nil) Controls randomness (0.0 to 1.0)
    # @option options [Integer] :max_output_tokens (nil) Maximum number of tokens to generate
    # @option options [Float] :top_p (nil) Nucleus sampling parameter (0.0 to 1.0)
    # @option options [Integer] :top_k (nil) Top-k sampling parameter
    #
    # @raise [GeminiCompletions::Error] if the API returns an error
    #
    # @return [Hash] The response from the API
    #
    def generate_content(contents, options = {})
      validate_contents!(contents)

      http_client = Faraday.new do |f|
        f.adapter :typhoeus
      end

      if @stream
        # Not really necessary, but I feel it might round some edge cases
        parser = EventStreamParser::Parser.new

        url = "#{BASE_URL}/models/#{@model}:streamGenerateContent?alt=sse&key=#{@api_key}"

        response = http_client.post(url) do |request|
          request.headers['Content-Type'] = 'application/json'
          request.body = build_request_body(contents, options).to_json

          puts "REQUEST BODY: #{request.body}"

          request.options.on_data = proc do |chunk, _|
            parser.feed(chunk) do |_type, data, _id, _reconnection_time|
              begin
                parsed_chunk_data = JSON.parse(data)
                parts = parsed_chunk_data.dig("candidates", 0, "content", "parts")
                uses_tools = parts.any? { |part| part['functionCall'] }
                yield parsed_chunk_data, uses_tools if block_given?

              rescue JSON::ParserError => e
                puts "Error parsing JSON: #{e.message}"
              end
            end
          end
        end

        if response.status == 200
          response
        else
          raise GeminiCompletions::Error.new(response.body)
        end
      else
        url = "#{BASE_URL}/models/#{@model}:generateContent?key=#{@api_key}"
        response = http_client.post(url, build_request_body(contents, options).to_json, {
          'Content-Type' => 'application/json'
        })

        parsed_response = JSON.parse(response.body.to_s)

        if response.status == 200
          parsed_response
        else
          raise GeminiCompletions::Error.new(parsed_response['error']['message'])
        end
      end
    end

    private

    def build_request_body(contents, options = {})
      body = {}

      if options[:systemInstruction]
        body[:system_instruction] = {
          parts: [{ text: options[:systemInstruction] }]
        }
      end

      body[:contents] = contents

      if options.any?
        body[:generationConfig] = {
          temperature: options[:temperature],
          maxOutputTokens: options[:max_output_tokens],
          topP: options[:top_p],
          topK: options[:top_k]
        }.compact

        # Setup and validate tools
        if options[:tools]
          body[:tools] = [{
            functionDeclarations: options[:tools].map(&:validate!).map(&:to_h)
          }]
        end
      end

      body
    end

    # TODO: Might be too slow for large arrays, might want to do without ActiveModel::Validations and go PORO
    def validate_contents!(contents)
      raise ArgumentError, "Contents must be an array" unless contents.is_a?(Array)

      contents.each do |message|
        puts "MESSAGE: #{message}"
        GeminiCompletions::Validators::Message.new(message).validate!
      end
    end
  end


end
