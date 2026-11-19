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

    @remaining_tokens : Int32?

    def initialize(@source : String, @max_depth : Int32, @limits : Limits)
      @bytes = @source.to_slice
      @token_end = @bytes.size
      @remaining_tokens = @limits.max_tokens
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
        if take_punctuation('[')
          array = take_punctuation('[')
          keys = path(0)
          expect_punctuation(']')
          expect_punctuation(']') if array
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
            child = Table.new
            if prior
              conflict(key, prior) unless prior.kind.array_of_tables?
              table[key.name].as(Array(Value)) << child
            else
              table[key.name] = [child] of Value
              @definitions[slot] = Definition.new(:array_of_tables, key.offset)
            end
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
      expect_punctuation('=')
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
      first = path_component(depth + 1)
      return {first} unless take_punctuation('.')

      keys = [] of Key
      keys << first
      loop do
        keys << path_component(depth + keys.size + 1)
        break unless take_punctuation('.')
      end
      keys
    end

    private def path_component(depth) : Key
      spaces
      check_depth(depth)
      start = @pos
      name = token { read_key }
      spaces
      Key.new(name, start)
    end

    private def read_key
      return string(multiline_allowed: false) if peek.in?('"', '\'')
      start = @pos
      while !eof? && BareKey.byte?(@bytes[@pos])
        advance
      end
      fail_at("expected a key") if @pos == start
      span(start)
    end

    private def value(depth) : Value
      check_depth(depth)
      case peek
      when '"', '\'' then token { string }
      when '['
        token { advance }
        array = [] of Value
        entries(']') { array << value(depth + 1) }
        array
      when '{'
        token { advance }
        table = Table.new
        entries('}') { assignment(table, depth) }
        table
      else
        token { scalar }
      end
    end

    private def entries(close, &)
      skip_layout
      until take_punctuation(close)
        yield
        skip_layout
        break if take_punctuation(close)
        expect_punctuation(',')
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
      return unless peek == '#'
      token do
        advance
        until eof? || peek.in?('\n', '\r')
          check_control
          advance
        end
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
        advance
      end
    end

    # Token limits use the source spelling, including quotes and escape bytes.
    # Layout outside tokens can use the full document. A failed parse discards
    # the parser, so only successful tokens need to restore the scan boundary.
    private def token(&)
      if (remaining = @remaining_tokens) && !eof?
        if remaining.zero?
          raise LimitError.new(:max_tokens, @limits.max_tokens.not_nil!, @source, @pos)
        end
        @remaining_tokens = remaining - 1
      end
      if maximum = @limits.max_token_bytes
        @token_end = @pos + Math.min(maximum, @bytes.size - @pos)
      end
      result = yield
      @token_end = @bytes.size
      result
    end

    private def advance(count = 1)
      if count > @token_end - @pos
        raise LimitError.new(:max_token_bytes, @limits.max_token_bytes.not_nil!, @source, @token_end)
      end
      @pos += count
    end

    private def take_punctuation(char)
      return false unless peek == char
      token { advance }
      true
    end

    private def expect_punctuation(char)
      fail_at("expected #{char.inspect}") unless take_punctuation(char)
    end

    private def take(char) : Bool
      return false unless peek == char
      advance
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
