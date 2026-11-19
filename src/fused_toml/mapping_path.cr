module FusedTOML
  private module MappingPath
    @path = [] of String | Int32

    def at(segment : String | Int32, &)
      @path << segment
      begin
        yield
      ensure
        @path.pop
      end
    end

    private def current_path : String
      String.build do |io|
        io << '$'
        @path.each do |segment|
          case segment
          when Int32 then io << '[' << segment << ']'
          when String
            if BareKey.valid?(segment)
              io << '.' << segment
            else
              io << '[' << segment.inspect << ']'
            end
          end
        end
      end
    end
  end
end
