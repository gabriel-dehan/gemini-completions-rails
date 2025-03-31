##
# Validates a tool definition according to Gemini and OpenAI function calling specs
#
# @see https://ai.google.dev/gemini-api/docs/function-calling
# @see https://platform.openai.com/docs/guides/function-calling
#
module GeminiCompletions
  module Validators
    class Tool
      include ActiveModel::Validations

      VALID_PARAMETER_TYPES = %w[object array string number integer boolean null].freeze
      NAME_REGEX = /\A[a-zA-Z0-9_]+\z/.freeze
      INVALID_NAME_MESSAGE = "cannot contain spaces or special characters".freeze

      attr_accessor :name, :description, :parameters

      def initialize(name:, description:, parameters: {})
        @name = name
        @description = description
        @parameters = parameters
      end

      validates :name, presence: true, format: {
        with: NAME_REGEX,
        message: INVALID_NAME_MESSAGE
      }
      validates :description, presence: true
      validate :validate_parameters
      validate :tool_registered

      private

      def tool_registered
        unless Gemini::Tool.find_by_name(name)
          errors.add(:name, "tool not registered")
        end
      end

      def validate_parameters
        # Parameters are optional
        if parameters
          return errors.add(:parameters, "must be a hash") unless parameters.is_a?(Hash)

          type = parameters['type'] || parameters[:type]
          return errors.add(:parameters, "must have a 'type' field") unless type
          return errors.add(:parameters, "type must be 'object' at root level") unless type == 'object'

          # Recursively validate the parameter schema
          validate_parameter_schema(parameters)
        end
      end

      def validate_parameter_schema(schema)
        type = schema[:type]
        unless VALID_PARAMETER_TYPES.include?(type)
          errors.add(:parameters, "invalid parameter type: #{type}")
          return
        end

        # Validate enum if present
        if schema[:enum]
          validate_enum(schema, schema[:enum])
        end

        # Validate type
        case type
        when 'object'
          validate_object_type(schema)
        when 'array'
          validate_array_type(schema)
        end

        # Validate description if present
        description = schema[:description]
        if description
          errors.add(:parameters, "description must be a string") unless description.is_a?(String)
        end
      end

      def validate_object_type(schema)
        properties = schema[:properties]
        unless properties.is_a?(Hash)
          errors.add(:parameters, "object properties must be a hash")
          return
        end

        # Validate each property
        properties.each do |property_name, property_schema|
          validate_property_name(property_name)
          validate_parameter_schema(property_schema)
        end

        # Validate required fields if present
        if required = schema[:required]
          validate_required_fields(required, properties)
        end
      end

      def validate_array_type(schema)
        items = schema[:items]
        if items.nil?
          errors.add(:parameters, "array must have items definition")
          return
        end

        # TODO: Probably a bit too loose
        validate_parameter_schema(items)
      end

      def validate_enum(schema, enum)
        unless enum.is_a?(Array)
          errors.add(:parameters, "enum must be an array")
          return
        end

        unless schema[:type] == 'string'
          errors.add(:parameters, "enum can only be used with string types")
          return
        end

        # Validate enum values are all strings
        unless enum.all? { |value| value.is_a?(String) }
          errors.add(:parameters, "enum values must be strings")
        end
      end

      def validate_property_name(name)
        unless name.match?(NAME_REGEX)
          errors.add(:parameters, "property name '#{name}' #{INVALID_NAME_MESSAGE}")
        end
      end

      def validate_required_fields(required, properties)
        unless required.is_a?(Array)
          errors.add(:parameters, "required must be an array")
          return
        end

        unless required.all? { |field| properties.key?(field.to_s) || properties.key?(field.to_sym) }
          errors.add(:parameters, "required fields must exist in properties")
        end
      end
    end
  end
end
