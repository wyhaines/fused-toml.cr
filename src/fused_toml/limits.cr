module FusedTOML
  # Optional inclusive budgets for one load. Zero is a valid budget.
  struct Limits
    getter max_document_bytes : Int32?, max_token_bytes : Int32?, max_tokens : Int32?

    def initialize(*, @max_document_bytes : Int32? = nil, @max_token_bytes : Int32? = nil, @max_tokens : Int32? = nil)
      raise ArgumentError.new("max_document_bytes must be nonnegative") if (max_document_bytes || 0) < 0
      raise ArgumentError.new("max_token_bytes must be nonnegative") if (max_token_bytes || 0) < 0
      raise ArgumentError.new("max_tokens must be nonnegative") if (max_tokens || 0) < 0
    end

    DEFAULT = new
  end

  # The first byte or token that exceeded a configured budget.
  class LimitError < ParseError
    getter limit_name : Symbol, maximum : Int32

    def initialize(@limit_name, @maximum, source : String, offset : Int32)
      super("#{limit_name} limit of #{maximum} exceeded", source, offset)
    end
  end
end
