module GeminiCompletions
  module Validators
    class Message
      include ActiveModel::Validations

      attr_accessor :role, :parts

      def initialize(message)
        @role = message[:role].to_s.downcase
        @parts = message[:parts] || []
      end

      validates :role, inclusion: { in: %w[user model] }
      validate :validate_parts_format

      private

      def validate_parts_format
        return if parts.all? do |part|
          part = part.with_indifferent_access
          part[:text] || part[:functionCall] || part[:functionResponse]
        end

        errors.add(:parts, 'must be an array of hashes with text, functionCall or functionResponse keys')
      end
    end
  end
end
