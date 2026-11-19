require "./ascii_string_scanner"
require "./strings"
require "./scalars"

module FusedTOML
  private class Parser
    private enum DefinitionKind
      Implicit
      Explicit
      Dotted
      ArrayOfTables
      Value
    end

    private record Definition, kind : DefinitionKind, offset : Int32
    private record Key, name : String, offset : Int32

    @definitions = {} of Tuple(UInt64, String) => Definition
    @pos = 0

    def initialize(@source : String, @max_depth : Int32)
      raise ArgumentError.new("max_depth must be between 1 and 256") unless (1..256).includes?(@max_depth)
      @bytes = @source.to_slice
    end

    def parse : Table
      unless @source.valid_encoding?
        reader = Char::Reader.new(@source)
        while reader.has_next? && !reader.error
          reader.next_char
        end
        fail_at("invalid UTF-8", reader.pos)
      end
      @pos = 3 if @source.starts_with?('\uFEFF')
      root = Table.new
      current = root
      depth = 0
      skip_layout
      until eof?
        if take('[')
          array = take('[')
          keys = path(0)
          expect(']')
          expect(']') if array
          current = header(root, keys, array)
          depth = keys.size
        else
          assignment(current, depth)
        end
        spaces
        comment
        fail_at("expected end of line") unless eof? || newline
        skip_layout
      end
      root
    end

    private def header(root, keys, array)
      table = root
      keys.each_with_index do |key, index|
        slot = {table.object_id, key.name}
        prior = @definitions[slot]?
        if index + 1 == keys.size
          if array
            conflict(key, prior) if prior && !prior.kind.array_of_tables?
            entries = prior ? table[key.name].as(Array(Value)) : [] of Value
            child = Table.new
            entries << child
            table[key.name] = entries
            @definitions[slot] ||= Definition.new(:array_of_tables, key.offset)
            return child
          end
          conflict(key, prior) if prior && !prior.kind.implicit?
          @definitions[slot] = Definition.new(:explicit, key.offset)
          return (table[key.name] ||= Table.new).as(Table)
        end
        if prior && prior.kind.array_of_tables?
          table = table[key.name].as(Array(Value)).last.as(Table)
        else
          conflict(key, prior) if prior && prior.kind.value?
          @definitions[slot] ||= Definition.new(:implicit, key.offset)
          table = (table[key.name] ||= Table.new).as(Table)
        end
      end
      raise "empty header path"
    end

    private def assignment(table, depth)
      keys = path(depth)
      expect('=')
      spaces
      keys.each_with_index do |key, index|
        slot = {table.object_id, key.name}
        prior = @definitions[slot]?
        if index + 1 == keys.size
          conflict(key, prior) if prior
          table[key.name] = value(depth + keys.size)
          @definitions[slot] = Definition.new(:value, key.offset)
        else
          if prior && !prior.kind.dotted? && !prior.kind.implicit?
            conflict(key, prior)
          end
          unless prior && prior.kind.dotted?
            @definitions[slot] = Definition.new(:dotted, key.offset)
          end
          table = (table[key.name] ||= Table.new).as(Table)
        end
      end
    end

    private def conflict(key, prior) : NoReturn
      raise ParseError.new("conflicting definition for #{key.name.inspect}", @source, key.offset, prior.offset)
    end

    private def path(depth)
      keys = [] of Key
      loop do
        spaces
        check_depth(depth + keys.size + 1)
        start = @pos
        if peek.in?('"', '\'')
          name = string(multiline_allowed: false)
        else
          while (char = peek).ascii_alphanumeric? || char.in?('-', '_')
            @pos += 1
          end
          fail_at("expected a key") if @pos == start
          name = span(start)
        end
        keys << Key.new(name, start)
        spaces
        break unless take('.')
      end
      keys
    end

    private def value(depth) : Value
      check_depth(depth)
      case peek
      when '"', '\'' then string
      when '['
        @pos += 1
        array = [] of Value
        entries(']') { array << value(depth + 1) }
        array
      when '{'
        @pos += 1
        table = Table.new
        entries('}') { assignment(table, depth) }
        table
      else
        scalar
      end
    end

    private def entries(close, &)
      skip_layout
      until take(close)
        yield
        skip_layout
        break if take(close)
        expect(',')
        skip_layout
      end
    end

    private def check_depth(depth)
      fail_at("maximum depth exceeded") if depth > @max_depth
    end

    private def skip_layout
      loop do
        spaces
        comment
        break unless newline
      end
    end

    private def comment
      return unless take('#')
      until eof? || peek.in?('\n', '\r')
        check_control
        @pos += 1
      end
    end

    private def check_control
      byte = @bytes[@pos]
      fail_at("unexpected control character") if (byte < 32 && byte != 9) || byte == 127
    end

    private def newline
      if take('\r')
        expect('\n')
        true
      else
        take('\n')
      end
    end

    private def spaces
      while peek.in?(' ', '\t')
        @pos += 1
      end
    end

    private def take(char) : Bool
      return false unless peek == char
      @pos += 1
      true
    end

    private def expect(char)
      fail_at("expected #{char.inspect}") unless take(char)
    end

    private def peek(ahead = 0) : Char
      ahead < @bytes.size - @pos ? @bytes[@pos + ahead].chr : '\0'
    end

    private def eof?
      @pos == @bytes.size
    end

    private def span(start)
      @source.byte_slice(start, @pos - start)
    end

    private def fail_at(reason, offset = @pos) : NoReturn
      raise ParseError.new(reason, @source, offset)
    end
  end
end
