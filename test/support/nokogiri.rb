module Nokogiri
  VERSION_INFO = 'test'

  module XML
    class Document
      def canonicalize
        ''
      end
    end

    class Schema
      def initialize(*)
      end

      def validate(*)
        []
      end
    end
  end
end
