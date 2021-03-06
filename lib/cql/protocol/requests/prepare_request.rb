# encoding: utf-8

module Cql
  module Protocol
    class PrepareRequest < RequestBody
      attr_reader :cql

      def initialize(cql)
        super(9)
        @cql = cql
      end

      def write(io)
        write_long_string(io, @cql)
      end

      def to_s
        %(PREPARE "#@cql")
      end

      def eql?(rq)
        self.class === rq && rq.cql == self.cql
      end
      alias_method :==, :eql?

      def hash
        @h ||= @cql.hash
      end
    end
  end
end
