# encoding: utf-8

module Cql
  module Protocol
    class QueryRequest < RequestBody
      attr_reader :cql, :consistency

      def initialize(cql, consistency)
        super(7)
        @cql = cql
        @consistency = consistency
      end

      def write(io)
        write_long_string(io, @cql)
        write_consistency(io, @consistency)
      end

      def to_s
        %(QUERY "#@cql" #{@consistency.to_s.upcase})
      end

      def eql?(rq)
        self.class === rq && rq.cql.eql?(self.cql) && rq.consistency.eql?(self.consistency)
      end
      alias_method :==, :eql?

      def hash
        @h ||= (@cql.hash * 31) ^ consistency.hash
      end
    end
  end
end
