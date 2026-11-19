module FusedTOML
  private module Input
    def self.document(source : String, maximum : Int32?) : String
      if maximum && source.bytesize > maximum
        raise LimitError.new(:max_document_bytes, maximum, source, maximum)
      end
      source
    end

    def self.document(source : IO, maximum : Int32?) : String
      # The extra byte distinguishes exact-length input from overflow without
      # consuming a whole chunk past the caller's budget.
      capacity = 16 * 1024
      capacity = Math.min(capacity, maximum.to_i64 + 1).to_i if maximum
      buffer = Bytes.new(capacity)
      String.build do |document|
        loop do
          size = buffer.size
          if maximum
            remaining = maximum - document.bytesize
            size = Math.min(size, remaining.to_i64 + 1).to_i
          end
          count = source.read(buffer[0, size])
          raise IO::Error.new("IO#read returned invalid byte count #{count}") unless 0 <= count <= size
          break if count.zero?
          document.write(buffer[0, count])
          if maximum && document.bytesize > maximum
            raise LimitError.new(:max_document_bytes, maximum, document.to_s, maximum)
          end
        end
      end
    end
  end
end
