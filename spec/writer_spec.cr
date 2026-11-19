require "spec"
require "../src/fused_toml"

describe "FusedTOML.dump" do
  it "sorts assignments before sections independently of insertion order" do
    first = FusedTOML.load("[[z]]\nk=1\n[[z]]\nk=2\n[a]\nz=3\na=4")
    second = FusedTOML.load("a={a=4,z=3}\nz=[{k=1},{k=2}]")
    first["x"] = 0_i64
    second["x"] = 0_i64
    expected = "x = 0\n\n[a]\na = 4\nz = 3\n\n[[z]]\nk = 1\n\n[[z]]\nk = 2\n"
    FusedTOML.dump(first).should eq(expected)
    FusedTOML.dump(second).should eq(expected)
    FusedTOML.load(expected).should eq(first)
  end

  it "attaches nested sections to their own array element and preserves empty elements" do
    input = FusedTOML.load(<<-TOML)
      [[pkg]]
      [pkg.meta]
      [[pkg.dep]]
      name = 'one'
      [[pkg.dep]]
      [[pkg]]
      [[pkg.dep]]
      name = 'two'
      [[pkg]]
      TOML
    output = FusedTOML.dump(input)
    FusedTOML.load(output).should eq(input)
    FusedTOML.dump(FusedTOML.load(output)).should eq(output)
  end

  it "writes inline tables inside mixed arrays and quotes each key independently" do
    doc = FusedTOML.load(%(mixed = [[], [{}], { z = {}, "a.b" = 1 }, 0]\n["a.b".""]\n"#" = true))
    output = FusedTOML.dump(doc)
    output.should contain(%(mixed = [[], [{}], {"a.b" = 1, z = {}}, 0]))
    output.should contain(%(["a.b".""]))
    FusedTOML.load(output).should eq(doc)
  end

  it "escapes all disallowed ASCII controls in values and keys" do
    key = (0..31).map(&.chr).join + "\u007f \"\\雪"
    doc = FusedTOML::Table.new
    doc[key] = key
    text = FusedTOML.dump(doc)
    text.lines.size.should eq(1)
    text.should contain("雪")
    FusedTOML.load(text).should eq(doc)
  end

  it "round trips float bits and distinguishes infinities and NaN" do
    floats = [-0.0, 0.0, 1.0, 1e18, Float64::MAX, 1_u64.unsafe_as(Float64),
              Float64::INFINITY, -Float64::INFINITY]
    floats.each do |number|
      table = FusedTOML::Table.new
      table["n"] = number
      restored = FusedTOML.load(FusedTOML.dump(table))["n"].as(Float64)
      restored.unsafe_as(UInt64).should eq(number.unsafe_as(UInt64))
    end
    table = FusedTOML.load("n=nan\nmin=-9223372036854775808\nmax=9223372036854775807")
    restored = FusedTOML.load(FusedTOML.dump(table))
    restored["n"].as(Float64).nan?.should be_true
    restored["min"].should eq(Int64::MIN)
    restored["max"].should eq(Int64::MAX)
  end

  it "serializes native temporal records with nanosecond precision and the original offset" do
    table = FusedTOML::Table.new
    date = FusedTOML::LocalDate.new(8, 2, 29)
    time = FusedTOML::LocalTime.new(0, 1, 2, 1)
    local = FusedTOML::LocalDateTime.new(date, time)
    table["date"] = date
    table["time"] = time
    table["local"] = local
    table["offset"] = FusedTOML::OffsetDateTime.new(local, "-00:00")
    text = FusedTOML.dump(table)
    text.should contain("offset = 0008-02-29T00:01:02.000000001-00:00")
    FusedTOML.load(text).should eq(table)
    table["offset"] = FusedTOML::OffsetDateTime.new(local, "z")
    FusedTOML.load(FusedTOML.dump(table))["offset"].as(FusedTOML::OffsetDateTime).offset.should eq("Z")
  end

  it "rejects invalid strings, dates, times, and offsets built by callers" do
    invalid = String.new(Bytes[0xff])
    local = FusedTOML::LocalDateTime.new(FusedTOML::LocalDate.new(2000, 1, 1), FusedTOML::LocalTime.new(1, 2, 3, 0))
    [invalid, FusedTOML::LocalDate.new(1900, 2, 29), FusedTOML::LocalDate.new(-1, 12, 1),
     FusedTOML::LocalTime.new(0, 0, 0, 1_000_000_000), FusedTOML::LocalTime.new(24, 0, 0, 0),
     FusedTOML::OffsetDateTime.new(local, "+24:00"), FusedTOML::OffsetDateTime.new(local, invalid)].each do |v|
      table = FusedTOML::Table.new
      table["v"] = v
      expect_raises(FusedTOML::EncodeError) { FusedTOML.dump(table) }
    end
    table = FusedTOML::Table.new
    table[invalid] = true
    expect_raises(FusedTOML::EncodeError) { FusedTOML.dump(table) }
  end

  it "round trips year zero and reports invalid days through the mapping API" do
    source = "date = 0000-02-29\nlocal = 0000-01-01T00:00:00\noffset = 0000-12-31T23:59:59Z\n"
    table = FusedTOML.load(source)
    table["date"].should eq(FusedTOML::LocalDate.new(0, 2, 29))
    FusedTOML.dump(table).should eq(source)

    expect_raises(FusedTOML::ParseError) { FusedTOML.load("date = 0000-02-30") }.byte_offset.should eq(7)
    invalid = FusedTOML::LocalDate.new(0, 2, 30)
    table["date"] = invalid
    expect_raises(FusedTOML::EncodeError) { FusedTOML.dump(table) }
    error = expect_raises(FusedTOML::EncodeError) { FusedTOML.dump({"days" => [invalid]}) }
    error.path.should eq("$.days[0]")
  end

  it "counts output depth like the reader and bounds cyclic inputs" do
    table = FusedTOML.load("[[a]]\nb=[{c=1},0]", max_depth: 4)
    text = FusedTOML.dump(table, max_depth: 4)
    FusedTOML.load(text, max_depth: 4).should eq(table)
    expect_raises(FusedTOML::EncodeError) { FusedTOML.dump(table, max_depth: 3) }
    expect_raises(ArgumentError) { FusedTOML.dump(table, max_depth: 257) }
    table["cycle"] = table
    expect_raises(FusedTOML::EncodeError) { FusedTOML.dump(table, max_depth: 4) }
  end

  it "emits the same document into a borrowed IO and propagates write errors" do
    io = IO::Memory.new
    table = FusedTOML.load("[a]\nb=1")
    io << "# prefix\n"
    FusedTOML.dump(table, io).should be_nil
    io.to_s.should eq("# prefix\n" + FusedTOML.dump(table))
    io.closed?.should be_false
    io.close
    expect_raises(IO::Error) { FusedTOML.dump(table, io) }
  end

  it "can write an empty root and an empty child table" do
    [FusedTOML.load(""), FusedTOML.load("[empty]")].each do |table|
      FusedTOML.load(FusedTOML.dump(table)).should eq(table)
    end
  end

  it "writes UTF-8 bytes to IO with a different text encoding" do
    io = IO::Memory.new
    io.set_encoding("UTF-16LE")
    io << "A"
    table = FusedTOML.load(%q("雪"."é" = ["a\tb", 1.25]))
    FusedTOML.dump(table, io)
    io << "B"
    io.to_slice.should eq(("A\0" + FusedTOML.dump(table) + "B\0").to_slice)
  end
end
