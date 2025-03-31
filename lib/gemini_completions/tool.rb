module GeminiCompletions
  class Tool
    class << self
      # Define a registry of all tools as a eigen class variable so it is shared across all instances
      @@defined_tools = {}

      # I don't know if this the cleanest, but this allows to register the tool when it's defined
      def name(name = nil)
        if name
          @name = name
          @@defined_tools[name] = self
        end

        @name
      end

      def description(description = nil)
        @description = description if description
        @description
      end

      def parameters(parameters = nil)
        @parameters = parameters if parameters
      end

      def handler(&block)
        @handler = block
      end

      def validate!
        validator = Validators::Tool.new(
          name: name,
          description: description,
          parameters: parameters
        )

        raise ArgumentError, validator.errors.full_messages.join(", ") unless validator.valid?
        raise ArgumentError, "Handler must be provided" unless @handler.respond_to?(:call)

        return self
      end

      def to_h
        {
          name: @name,
          description: @description,
          parameters: @parameters
        }
      end

      def call(params)
        @handler.call(params)
      end

      # Tools helper methods
      def find_by_name(name)
        @@defined_tools[name]
      end

      def all
        @@defined_tools
      end
    end
  end
end
