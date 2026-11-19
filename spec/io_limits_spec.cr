require "spec"
require "../src/fused_toml"
require "./support/chunked_io"

private alias ChunkedInput = StreamSpecSupport::ChunkedIO

private def matching_error(source, limits = FusedTOML::Limits::DEFAULT, max_depth = 128)
  string_error = expect_raises(FusedTOML::ParseError) { FusedTOML.load(source, limits: limits, max_depth: max_depth) }
  io = ChunkedInput.new(source, max_chunk: 7)
  io_error = expect_raises(FusedTOML::ParseError) { FusedTOML.load(io, limits: limits, max_depth: max_depth) }
  io.closed_called.should be_false
  {io_error.class, io_error.message, io_error.byte_offset, io_error.line, io_error.column,
   io_error.previous_offset, io_error.previous_line, io_error.previous_column}.should eq(
    {string_error.class, string_error.message, string_error.byte_offset, string_error.line, string_error.column,
     string_error.previous_offset, string_error.previous_line, string_error.previous_column})
  string_error
end

describe "FusedTOML IO input" do
  it "matches String input at every split, including BOM, UTF-8, CRLF, quotes and escapes" do
    source = "\uFEFF[[services]]\r\n" + %q("☃.name" = """a\u00E9) + "\r\n😀\"\"\"\r\n" +
             "schedule = 2024-02-29 12:34:56.123456789-00:30\nvalues = [1, {q=2}, 'three']"
    expected = FusedTOML.load(source)
    (1...source.bytesize).each do |cut|
      io = ChunkedInput.new(source, chunks: [cut])
      FusedTOML.load(io).should eq(expected)
      io.closed_called.should be_false
    end
    FusedTOML.load(ChunkedInput.new(source, max_chunk: 1)).should eq(expected)
  end

  it "starts at the current position and leaves the source open" do
    io = IO::Memory.new("discard\na=42")
    io.gets
    FusedTOML.load(io, Hash(String, Int32)).should eq({"a" => 42})
    io.closed?.should be_false
    io.pos.should eq(io.size)
  end

  it "treats the first zero-length result as EOF, including on an empty source" do
    io = ChunkedInput.new("x=1bad", chunks: [3], zero_on_read: 2, read_budget: 2)
    FusedTOML.load(io)["x"].should eq(1_i64)
    io.bytes_read.should eq(3)
    io.read_calls.should eq(2)
    FusedTOML.load(ChunkedInput.new("", read_budget: 1)).should be_empty
    truncated = ChunkedInput.new("x='ok'", chunks: [3], zero_on_read: 2, read_budget: 2)
    expect_raises(FusedTOML::ParseError, /unterminated string/) { FusedTOML.load(truncated) }
  end

  it "propagates read failures and rejects invalid read counts" do
    io = ChunkedInput.new("x=1", fail_on_read: 2)
    expect_raises(IO::Error, "injected read failure") { FusedTOML.load(io) }
    io.closed_called.should be_false
    [-1, Int32::MAX].each do |n|
      bad = StreamSpecSupport::InvalidReadCountIO.new(n)
      expect_raises(IO::Error, /invalid byte count/) { FusedTOML.load(bad) }
      bad.read_calls.should eq(1)
    end
  end

  it "retains both declaration locations and reports malformed UTF-8 consistently" do
    source = "# 😀\r\n\"雪\" = 1\r\n'雪' = 2"
    err = matching_error(source)
    {err.byte_offset, err.line, err.column}.should eq({source.byte_index('\''), 3, 1})
    {err.previous_offset, err.previous_line, err.previous_column}.should eq({source.byte_index('"'), 2, 1})
    bad = "#é\n# " + String.new(Bytes[0xf0, 0x9f, 0x98])
    err = matching_error(bad)
    {err.byte_offset, err.line, err.column}.should eq({6, 2, 3})
    err.previous_line.should be_nil
    err.previous_column.should be_nil
  end
end

describe FusedTOML::Limits do
  it "validates budgets and depth before reading" do
    expect_raises(ArgumentError) { FusedTOML::Limits.new(max_document_bytes: -1) }
    expect_raises(ArgumentError) { FusedTOML::Limits.new(max_token_bytes: -1) }
    expect_raises(ArgumentError) { FusedTOML::Limits.new(max_tokens: -1) }
    io = ChunkedInput.new("", read_budget: 0)
    expect_raises(ArgumentError) { FusedTOML.load(io, max_depth: 0) }
    io.read_calls.should eq(0)
  end

  it "enforces the document cap at ingress, with at most one extra byte read" do
    source = "#雪\r\n" + "a='#{"x" * 20_000}'"
    limit = FusedTOML::Limits.new(max_document_bytes: source.bytesize)
    FusedTOML.load(ChunkedInput.new(source), limits: limit).should eq(FusedTOML.load(source, limits: limit))
    [0, 1, 2, 3, 6, 16384, source.bytesize - 1].each do |n|
      limits = FusedTOML::Limits.new(max_document_bytes: n)
      io = ChunkedInput.new(source)
      error = expect_raises(FusedTOML::LimitError) { FusedTOML.load(io, limits: limits) }
      io.bytes_read.should eq(n + 1)
      {error.limit_name, error.maximum, error.byte_offset}.should eq({:max_document_bytes, n, n})
      err = matching_error(source, limits)
      err.column.should eq(2) if n == 2 || n == 3
    end
    zero = FusedTOML::Limits.new(max_document_bytes: 0, max_tokens: 0, max_token_bytes: 0)
    FusedTOML.load(ChunkedInput.new(""), limits: zero).should be_empty
  end

  it "counts raw bytes of each key, comment and scalar through its closing delimiter" do
    [{"", "bare-key", "=0"}, {"", %q("☃.x"), "=0"}, {"", "#😀abc", "\r\n"},
     {"x=", "'''literal'''", ""}, {"x=", "'''雪雪雪''\t😀\r\nend'''", ""}, {"x=", "\"\"\"a\\ \t\r\n    b\"\"\"\"\"", ""},
     {"x=", %q("\U0001F600\u00FF\x1B"), ""}, {"x=", %q("雪é😀雪é😀"), ""}, {"x=", "2001-01-01 12:00:00Z", ""},
     {"x=", "0x7fff_ffff", ""}, {"x=", "'#{"x" * 33}'", ""}].each do |(prefix, literal, suffix)|
      source = prefix + literal + suffix
      exact = FusedTOML::Limits.new(max_token_bytes: literal.bytesize)
      FusedTOML.load(ChunkedInput.new(source), limits: exact).should eq(FusedTOML.load(source))
      (1...literal.bytesize).each do |n|
        err = matching_error(source, FusedTOML::Limits.new(max_token_bytes: n)).as(FusedTOML::LimitError)
        {err.limit_name, err.maximum, err.byte_offset}.should eq({:max_token_bytes, n, prefix.bytesize + n})
      end
    end
  end

  it "counts each punctuation byte and whole literals, skipping whitespace and BOM" do
    tokens = ["[", "[", "svc", "]", "]", "x", ".", "y", "=", "[", "true", ",", "{", "k", "=", "'v'", "}", "]", "#end"]
    source = "\uFEFF \t"
    offsets = [] of Int32
    tokens.each_with_index do |token, index|
      source += "\r\n" if index == 5
      offsets << source.bytesize
      source += token
    end
    exact = FusedTOML::Limits.new(max_tokens: tokens.size)
    FusedTOML.load(ChunkedInput.new(source), limits: exact).should eq(FusedTOML.load(source))
    offsets.each_with_index do |offset, n|
      err = matching_error(source, FusedTOML::Limits.new(max_tokens: n)).as(FusedTOML::LimitError)
      {err.limit_name, err.maximum, err.byte_offset}.should eq({:max_tokens, n, offset})
    end
    zero = FusedTOML::Limits.new(max_tokens: 0, max_token_bytes: 0)
    FusedTOML.load("\uFEFF \r\n\t", limits: zero).should be_empty
    missing = matching_error("x=", FusedTOML::Limits.new(max_tokens: 2))
    missing.class.should eq(FusedTOML::ParseError)
    missing.byte_offset.should eq(2)
  end

  it "enforces the same budgets before typed mapping or ignoring a field" do
    limits = FusedTOML::Limits.new(max_tokens: 3, max_token_bytes: 2)
    FusedTOML.load(ChunkedInput.new("x=42", max_chunk: 1), Hash(String, Int32), limits: limits).should eq({"x" => 42})
    ["x=123", "x=1\ny=2"].each do |source|
      err = matching_error(source, limits)
      ex = expect_raises(FusedTOML::LimitError) { FusedTOML.load(ChunkedInput.new(source), Hash(String, String), limits: limits) }
      ex.byte_offset.should eq(err.byte_offset)
    end
  end

  it "bounds long dotted paths and nested inline values before descending" do
    path = Array.new(5000, "x").join('.') + "=1"
    matching_error(path, max_depth: 128).byte_offset.should eq(256)
    nested = "x=" + "{x=" * 1000 + "1" + "}" * 1000
    matching_error(nested, max_depth: 128).byte_offset.should eq(2 + 3 * 127 + 1)
  end

  it "checks a long fractional-second token before conversion and truncates to nanoseconds" do
    literal = "12:34:56." + "1234567890" * 5000
    source = "t=" + literal
    limits = FusedTOML::Limits.new(max_token_bytes: literal.bytesize)
    time = FusedTOML.load(ChunkedInput.new(source, max_chunk: 73), limits: limits)["t"].as(FusedTOML::LocalTime)
    time.nanosecond.should eq(123456789)
    err = matching_error(source, FusedTOML::Limits.new(max_token_bytes: 512))
    err.byte_offset.should eq(514)
  end
end
