require "spec"
require "../src/fused_toml"

describe FusedTOML do
  it "lets a header declare an implicit parent" do
    table = FusedTOML.load("[service.http]\nport=8080\n[service]\nname='api'")
    service = table["service"].as(FusedTOML::Table)
    service["http"].as(FusedTOML::Table)["port"].should eq(8080_i64)
    service["name"].should eq("api")
  end

  it "reports both declarations after dotted assignment, including Unicode columns" do
    error = expect_raises(FusedTOML::ParseError) do
      FusedTOML.load("a.'é'.c=1\r\n[a.'é']\n")
    end
    error.byte_offset.should eq(15)
    error.line.should eq(2)
    error.column.should eq(4)
    error.previous_offset.should eq(2)
    error.message.to_s.should contain("first defined at 1:3")
  end

  it "resolves a nested array-of-tables header against the most recent parent" do
    doc = FusedTOML.load("[[pkg]]\n[[pkg.dep]]\nx=1\n[[pkg]]\n[[pkg.dep]]\nx=2")
    doc["pkg"].as(Array(FusedTOML::Value)).map do |pkg|
      deps = pkg.as(FusedTOML::Table)["dep"].as(Array(FusedTOML::Value))
      deps.size.should eq(1)
      deps.first.as(FusedTOML::Table)["x"]
    end.should eq([1_i64, 2_i64])
  end

  it "reports the first array-of-tables declaration after repeated headers" do
    error = expect_raises(FusedTOML::ParseError) { FusedTOML.load("[[s]]\n[[s]]\n[s]") }
    error.previous_offset.should eq(2)
    error.previous_line.should eq(1)
    error.line.should eq(3)
  end

  it "seals inline tables and distinguishes dots in a quoted component" do
    doc = FusedTOML.load(%("a.b" = { c = 1, }\na.b = false))
    doc["a.b"].as(FusedTOML::Table)["c"].should eq(1_i64)
    doc["a"].as(FusedTOML::Table)["b"].should eq(false)
    expect_raises(FusedTOML::ParseError) { FusedTOML.load(%("a.b" = {}\n["a.b".c])) }
    expect_raises(FusedTOML::ParseError) { FusedTOML.load("a = {b={}, b.c=1}") }
    expect_raises(FusedTOML::ParseError) { FusedTOML.load("a=false\na.b=1") }
  end

  it "keeps all four temporal kinds and truncates excess fractional digits" do
    doc = FusedTOML.load("d=2000-02-29\nt=07:32\nl=2000-02-29 07:32:00.1234567899\no=2000-02-29t07:32-00:30")
    date = FusedTOML::LocalDate.new(2000, 2, 29)
    time = FusedTOML::LocalTime.new(7, 32, 0, 0)
    doc["d"].should eq(date)
    doc["t"].should eq(time)
    doc["l"].as(FusedTOML::LocalDateTime).time.nanosecond.should eq(123456789)
    doc["o"].should eq(FusedTOML::OffsetDateTime.new(FusedTOML::LocalDateTime.new(date, time), "-00:30"))
  end

  it "enforces the integer domain and distinguishes signed zero from an integer" do
    doc = FusedTOML.load("min=-9223372036854775808\nmax=0x7fff_ffff_ffff_ffff\nz=-0.0\nn=+nan")
    doc["min"].should eq(Int64::MIN)
    doc["max"].should eq(Int64::MAX)
    (1.0 / doc["z"].as(Float64)).should eq(-Float64::INFINITY)
    doc["n"].as(Float64).nan?.should be_true
    expect_raises(FusedTOML::ParseError) { FusedTOML.load("over=0x8000000000000000") }
  end

  it "distinguishes a padded negative exponent from a date" do
    source = "value = 1.0e-000001\nwhen = 2000-02-29 12:00:00"
    [source, IO::Memory.new(source)].each do |input|
      table = FusedTOML.load(input)
      table["value"].should eq(0.1)
      table["when"].should be_a(FusedTOML::LocalDateTime)
    end
  end

  it "rejects second 60 consistently in the reader and writer" do
    expect_raises(FusedTOML::ParseError) { FusedTOML.load("at=2016-12-31T23:59:60Z") }
    table = FusedTOML::Table.new
    table["at"] = FusedTOML::LocalTime.new(23, 59, 60, 0)
    expect_raises(FusedTOML::EncodeError) { FusedTOML.dump(table) }
  end

  it "rejects malformed input with a parse location" do
    ["x=2000-123☃", "x='a'\0", "a=1\r", "a=1\na=2", %q(x="\uD800"), "d=1900-02-29"].each do |source|
      expect_raises(FusedTOML::ParseError) { FusedTOML.load(source) }
    end
    malformed = String.new(Bytes[35, 32, 0xe2, 0x82])
    expect_raises(FusedTOML::ParseError) { FusedTOML.load(malformed) }.byte_offset.should eq(2)
  end

  it "handles control bytes and escapes at every alignment of the basic-string scanner" do
    (0..23).each do |size|
      prefix = "a" * size + "雪é😀"
      source = "k=\"#{prefix}\\x7f☃\\e\t!\""
      FusedTOML.load(source)["k"].should eq(prefix + "\u007f☃\e\t!")
      expect_raises(FusedTOML::ParseError) { FusedTOML.load("k=\"#{prefix}\u007f\"") }
    end
  end

  it "bounds dotted keys, current header depth and nested containers" do
    FusedTOML.load("[a]\nb=[1]", max_depth: 3)
    ["[a]\nb=[1]", "a.b.c=1", "a={b.c=1}", "[[a.b.c]]"].each do |source|
      expect_raises(FusedTOML::ParseError) { FusedTOML.load(source, max_depth: 2) }
    end
    expect_raises(ArgumentError) { FusedTOML.load("", max_depth: 257) }
  end
end
