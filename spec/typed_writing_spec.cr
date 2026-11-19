require "spec"
require "../src/fused_toml"

private module TypedWritingSpec
  module Seconds
    def self.from_toml(value : FusedTOML::Value) : Time::Span
      value.as(Int64).seconds
    end

    class_property writes = 0

    def self.to_toml(value : Time::Span) : Int64
      self.writes += 1
      raise ArgumentError.new("expected whole seconds") unless value.nanoseconds.zero?
      value.to_i
    end
  end

  class Endpoint
    include FusedTOML::Serializable

    @[FusedTOML::Field(key: "bind.port")]
    property port : UInt16
    getter enabled : Bool = false
    getter label : String?
  end

  struct Config
    include FusedTOML::Serializable

    getter endpoints : Array(Endpoint)
    @[FusedTOML::Field(converter: Seconds)]
    getter wait : Time::Span
  end

  module StringOrPort
    def self.from_toml(value : FusedTOML::Value) : String | Int32
      value.is_a?(String) ? value : value.as(Int64).to_i32
    end

    def self.to_toml(value : String | Int32) : FusedTOML::Value
      value.is_a?(String) ? value : value.to_i64
    end
  end

  struct ConvertedUnion
    include FusedTOML::Serializable

    @[FusedTOML::Field(key: "", converter: StringOrPort)]
    property address : String | Int32
  end

  class Node
    include FusedTOML::Serializable
    getter children = [] of Node
    property value = 0

    def initialize
    end
  end

  struct Empty
    include FusedTOML::Serializable

    def initialize
    end
  end

  class Optional
    include FusedTOML::Serializable
    property name : String? = "default"
    @[FusedTOML::Field(key: "job.timeout", converter: Seconds)]
    property timeout : Time::Span?
    property empty = Empty.new
    property overrides = {} of String => Int32

    def initialize
    end
  end

  struct Raw
    include FusedTOML::Serializable
    getter data : FusedTOML::Value

    def initialize(@data)
    end
  end
end

describe "typed TOML writing" do
  it "reports the path of an identity hash collision before writing any bytes" do
    ports = Hash(String, Int32).new.compare_by_identity
    ports["http"] = 80
    ports["https"] = 443
    FusedTOML.load(FusedTOML.dump(ports)).should eq(FusedTOML.load("http=80\nhttps=443"))

    ports[String.new("http".to_slice)] = 8080
    expect_raises(FusedTOML::EncodeError) { FusedTOML.dump(ports) }.path.should eq("$.http")
    io = IO::Memory.new
    error = expect_raises(FusedTOML::EncodeError, /duplicate TOML key "http"/) do
      FusedTOML.dump({"services" => [ports]}, io)
    end
    error.path.should eq("$.services[0].http")
    io.size.should eq(0)
  end

  it "loads, edits and dumps a model and a typed root hash through the public APIs" do
    config = FusedTOML.load(%(wait=5\n[[endpoints]]\n"bind.port"=80), TypedWritingSpec::Config)
    config.endpoints.first.port = 443_u16
    table = FusedTOML.load(%(wait=5\n[[endpoints]]\n"bind.port"=443\nenabled=false))
    expected = FusedTOML.dump(table)
    config.to_toml.should eq(expected)
    FusedTOML.dump(config).should eq(expected)
    io = IO::Memory.new
    config.to_toml(io).should be_nil
    io.to_s.should eq(expected)
    io.clear
    FusedTOML.dump(config, io).should be_nil
    io.to_s.should eq(expected)
    restored = FusedTOML.load(expected, TypedWritingSpec::Config)
    restored.endpoints.first.port.should eq(443)
    restored.wait.should eq(5.seconds)
    configs = {"west" => config}
    wrapped = FusedTOML::Table.new
    wrapped["west"] = table
    FusedTOML.dump(configs).should eq(FusedTOML.dump(wrapped))
    io.clear
    FusedTOML.dump(configs, io).should be_nil
    io.to_s.should eq(FusedTOML.dump(wrapped))
    west = FusedTOML.load(io.to_s, Hash(String, TypedWritingSpec::Config))["west"]
    west.endpoints.first.port.should eq(443)
    west.wait.should eq(5.seconds)
  end

  it "emits defaults and empty containers, and omits nil fields before conversion" do
    object = TypedWritingSpec::Optional.new
    TypedWritingSpec::Seconds.writes = 0
    table = FusedTOML.load(object.to_toml)
    table.should eq(FusedTOML.load(%(name="default"\n[empty]\n[overrides])))
    TypedWritingSpec::Seconds.writes.should eq(0)
    object.name = nil
    object.timeout = 0.seconds
    output = object.to_toml
    FusedTOML.load(output).should eq(FusedTOML.load(%("job.timeout"=0\n[empty]\n[overrides])))
    TypedWritingSpec::Seconds.writes.should eq(1)
    FusedTOML.load(output, TypedWritingSpec::Optional).name.should eq("default")
  end

  it "writes an annotated union through a converter under an empty wire key" do
    value = FusedTOML.load(%("" = "localhost"), TypedWritingSpec::ConvertedUnion)
    FusedTOML.load(value.to_toml)[""].should eq("localhost")
    value.address = 8080
    FusedTOML.load(value.to_toml, TypedWritingSpec::ConvertedUnion).address.should eq(8080)
  end

  it "preserves integer boundaries, float kinds and typed root key order" do
    a = {"min" => Int64::MIN.to_i128, "max" => Int64::MAX.to_i128}
    b = {"max" => Int64::MAX.to_i128, "min" => Int64::MIN.to_i128}
    FusedTOML.dump(a).should eq(FusedTOML.dump(b))
    FusedTOML.load(FusedTOML.dump(a), Hash(String, Int128)).should eq(a)
    expect_raises(FusedTOML::EncodeError, /Int64 range/) do
      FusedTOML.dump({"n" => [Int64::MIN.to_i128 - 1]})
    end.path.should eq("$.n[0]")
    expect_raises(FusedTOML::EncodeError, /Int64 range/) do
      FusedTOML.dump({"n" => [Int64::MAX.to_u64 + 1]})
    end.path.should eq("$.n[0]")
    numbers = {"n" => [-0.0_f32, 0.1_f32, Float32::INFINITY, -Float32::INFINITY, Float32::NAN]}
    result = FusedTOML.load(FusedTOML.dump(numbers), Hash(String, Array(Float32)))["n"]
    result[0, 4].map(&.unsafe_as(UInt32)).should eq(numbers["n"][0, 4].map(&.unsafe_as(UInt32)))
    result.last.nan?.should be_true
  end

  it "preserves all native temporal types in raw data and nested collections" do
    table = FusedTOML.load("d=2000-02-29\nt=07:32:00.000000001\nl=2000-02-29T07:32\no=2000-02-29T07:32-00:30")
    model = TypedWritingSpec::Raw.new(table)
    FusedTOML.load(model.to_toml)["data"].should eq(table)
    table["bad"] = FusedTOML::LocalDate.new(1900, 2, 29)
    err = expect_raises(FusedTOML::EncodeError) { model.to_toml }
    err.path.should eq("$.data.bad")
    bad = String.new(Bytes[0xff])
    expect_raises(FusedTOML::EncodeError, /invalid UTF-8/) { FusedTOML.dump({bad => 1}) }
  end

  it "rejects nil array elements and hash entries at their precise external paths" do
    array = [1_i32, nil]
    ex = expect_raises(FusedTOML::EncodeError) { FusedTOML.dump({"a.b" => array}) }
    ex.path.should eq(%($["a.b"][1]))
    ex = expect_raises(FusedTOML::EncodeError) { FusedTOML.dump({"a" => {"" => nil}}) }
    ex.path.should eq(%($.a[""]))
  end

  it "gives typed and native sections and inline arrays the same depth boundary" do
    table = FusedTOML.load("data=[{x=[{y=1}]}]")
    model = TypedWritingSpec::Raw.new(table["data"])
    model.to_toml(max_depth: 3).should eq(FusedTOML.dump(table, max_depth: 3))
    err = expect_raises(FusedTOML::EncodeError) { model.to_toml(max_depth: 2) }
    err.path.should eq("$.data[0].x[0].y")

    inline = FusedTOML.load("data=[{x=[{y=1}]},0]")
    model = TypedWritingSpec::Raw.new(inline["data"])
    model.to_toml(max_depth: 5).should eq(FusedTOML.dump(inline, max_depth: 5))
    expect_raises(FusedTOML::EncodeError) { FusedTOML.dump(inline, max_depth: 4) }
    err = expect_raises(FusedTOML::EncodeError) { model.to_toml(max_depth: 4) }
    err.path.should eq("$.data[0].x[0].y")
    expect_raises(ArgumentError) { model.to_toml(max_depth: 257) }
  end

  it "rejects active reference cycles and accepts children shared between siblings" do
    parent = TypedWritingSpec::Node.new
    child = TypedWritingSpec::Node.new
    parent.children << child << child
    children = FusedTOML.load(parent.to_toml, TypedWritingSpec::Node).children
    children.size.should eq(2)
    children.map(&.value).should eq([0, 0])
    child.children << parent
    err = expect_raises(FusedTOML::EncodeError, /cyclic/) { parent.to_toml }
    err.path.should eq("$.children[0].children[0]")
    data = FusedTOML::Table.new
    data["cycle"] = data
    err = expect_raises(FusedTOML::EncodeError, /cyclic/) { TypedWritingSpec::Raw.new(data).to_toml }
    err.path.should eq("$.data.cycle")
  end

  it "keeps converter causes and completes mapping before touching a borrowed IO" do
    object = TypedWritingSpec::Optional.new
    object.timeout = 1.nanosecond
    io = IO::Memory.new
    io << "# existing\n"
    err = expect_raises(FusedTOML::EncodeError, /expected whole seconds/) do
      FusedTOML.dump({"tasks" => [object]}, io)
    end
    err.path.should eq(%($.tasks[0]["job.timeout"]))
    err.cause.should be_a(ArgumentError)
    io.to_s.should eq("# existing\n")
    object.timeout = nil
    object.to_toml(io).should be_nil
    io.to_s.should eq("# existing\n" + object.to_toml)
    io.closed?.should be_false
    io.close
    expect_raises(IO::Error) { object.to_toml(io) }
  end
end
