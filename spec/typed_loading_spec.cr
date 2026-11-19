require "spec"
require "../src/fused_toml"

private module TypedLoadingSpec
  struct Endpoint
    include FusedTOML::Serializable
    include FusedTOML::Serializable::Strict

    @[FusedTOML::Field(key: "bind.port")]
    getter port : UInt16
    getter enabled : Bool = true
    getter label : String?
  end

  class Config
    include FusedTOML::Serializable

    getter endpoints : Array(Endpoint)
    getter counts : Hash(String, Array(Int8)) = {} of String => Array(Int8)
    getter description : String? = "default"
  end

  module Seconds
    def self.from_toml(value : FusedTOML::Value) : Time::Span
      seconds = value.as(Int64)
      raise ArgumentError.new("negative duration") if seconds < 0
      seconds.seconds
    end
  end

  struct Timer
    include FusedTOML::Serializable

    @[FusedTOML::Field(key: "wait-time", converter: TypedLoadingSpec::Seconds)]
    getter wait : Time::Span = 1.second
  end

  class Node
    include FusedTOML::Serializable

    getter name : String
    getter children = [] of Node

    def initialize(@name : String)
    end
  end

  class LabeledNode < Node
    getter label : String

    def initialize(name : String, @label : String)
      super(name)
    end
  end

  struct Calendar
    include FusedTOML::Serializable

    getter date : FusedTOML::LocalDate
    getter time : FusedTOML::LocalTime
    getter local : FusedTOML::LocalDateTime
    getter offset : FusedTOML::OffsetDateTime
  end

  struct Raw
    include FusedTOML::Serializable

    getter any : FusedTOML::Value
    getter optional : FusedTOML::Value?
    getter flags : Array(Bool?)?
    getter map : FusedTOML::Table
    getter array : Array(FusedTOML::Value)
  end

  struct Empty
    include FusedTOML::Serializable
    include FusedTOML::Serializable::Strict
  end
end

describe "FusedTOML.load(source, T)" do
  it "maps resolved tables, arrays of tables, dotted assignments and quoted field names" do
    settings = FusedTOML.load(<<-TOML, TypedLoadingSpec::Config)
      unused = "ignored at this level"
      counts."floor.1" = [-128, 127]
      [[endpoints]]
      "bind.port" = 65535
      enabled = false
      [[endpoints]]
      "bind.port" = 0
      label = "local"
      TOML
    settings.counts.should eq({"floor.1" => [-128_i8, 127_i8]})
    settings.description.should eq("default")
    settings.endpoints.map(&.port).should eq([65535_u16, 0_u16])
    settings.endpoints.map(&.enabled).should eq([false, true])
    settings.endpoints.map(&.label).should eq([nil, "local"])
  end

  it "reports the external key and failing array index for missing or mistyped fields" do
    ["{}", %({"bind.port"="443"})].each do |entry|
      ex = expect_raises(FusedTOML::DecodeError) do
        FusedTOML.load(%(endpoints=[{"bind.port"=80},#{entry}]), TypedLoadingSpec::Config)
      end
      ex.path.should eq(%($.endpoints[1]["bind.port"]))
    end
    ex = expect_raises(FusedTOML::DecodeError) { FusedTOML.load("endpoints=[0]", TypedLoadingSpec::Config) }
    ex.path.should eq("$.endpoints[0]")
    ex = expect_raises(FusedTOML::DecodeError) { FusedTOML.load("endpoints=[]\ndescription=0", TypedLoadingSpec::Config) }
    ex.path.should eq("$.description")
  end

  it "applies strictness to the declaring type and quotes unknown keys" do
    ex = expect_raises(FusedTOML::DecodeError, /unknown field/) do
      FusedTOML.load(%(endpoints=[{"bind.port"=1, "odd.key"=false}]), TypedLoadingSpec::Config)
    end
    ex.path.should eq(%($.endpoints[0]["odd.key"]))
    FusedTOML.load("", TypedLoadingSpec::Empty)
    expect_raises(FusedTOML::DecodeError) { FusedTOML.load(%("" = 1), TypedLoadingSpec::Empty) }.path.should eq(%($[""]))
  end

  it "preserves defaults for absent fields and passes present values to converters" do
    FusedTOML.load("", TypedLoadingSpec::Timer).wait.should eq(1.second)
    FusedTOML.load("wait-time=0", TypedLoadingSpec::Timer).wait.should eq(0.seconds)
    ex = expect_raises(FusedTOML::DecodeError, /negative duration/) do
      FusedTOML.load("first={wait-time=-1}", Hash(String, TypedLoadingSpec::Timer))
    end
    ex.path.should eq("$.first.wait-time")
    ex.cause.should be_a(ArgumentError)
  end

  it "checks signed and unsigned bounds in typed collections" do
    FusedTOML.load("port=255", Hash(String, UInt8)).should eq({"port" => 255_u8})
    [-1, 256].each do |n|
      expect_raises(FusedTOML::DecodeError, /UInt8 range/) { FusedTOML.load("p=#{n}", Hash(String, UInt8)) }.path.should eq("$.p")
    end
    ex = expect_raises(FusedTOML::DecodeError, /Int8 range/) do
      FusedTOML.load(%(endpoints=[]\ncounts."r.1"=[-129]), TypedLoadingSpec::Config)
    end
    ex.path.should eq(%($.counts["r.1"][0]))
    FusedTOML.load("n=-9223372036854775808", Hash(String, Int128))["n"].should eq(Int64::MIN.to_i128)
    FusedTOML.load("n=9223372036854775807", Hash(String, UInt128))["n"].should eq(Int64::MAX.to_u128)
  end

  it "preserves numeric kinds and rejects overflow when narrowing floats" do
    FusedTOML.load("n=-inf", Hash(String, Float32))["n"].should eq(-Float32::INFINITY)
    FusedTOML.load("n=0.25", Hash(String, Float64))["n"].should eq(0.25)
    expect_raises(FusedTOML::DecodeError) { FusedTOML.load("n=1e100", Hash(String, Float32)) }
    expect_raises(FusedTOML::DecodeError) { FusedTOML.load("n=2", Hash(String, Float64)) }
    expect_raises(FusedTOML::DecodeError) { FusedTOML.load("n=2.0", Hash(String, Int32)) }
  end

  it "supports recursive models with an existing constructor" do
    node = FusedTOML.load(%(name="root"\n[[children]]\nname="leaf"), TypedLoadingSpec::Node)
    node.name.should eq("root")
    node.children.first.name.should eq("leaf")
    node.children.first.children.should be_empty
    TypedLoadingSpec::Node.new("manual").name.should eq("manual")
  end

  it "maps all native temporal types and preserves raw subtrees" do
    calendar = FusedTOML.load("date=2000-01-01\ntime=12:00\nlocal=2000-01-01T12:00\noffset=2000-01-01T12:00-05:30", TypedLoadingSpec::Calendar)
    calendar.local.date.should eq(calendar.date)
    calendar.local.time.should eq(calendar.time)
    calendar.offset.local.should eq(calendar.local)
    calendar.offset.offset.should eq("-05:30")
    raw = FusedTOML.load("any=false\nmap.k=0\narray=[1,'two']", TypedLoadingSpec::Raw)
    raw.any.should eq(false)
    raw.map["k"].should eq(0_i64)
    raw.array.should eq([1_i64, "two"])
    raw.optional.should be_nil
    raw.flags.should be_nil
    raw = FusedTOML.load("any=1\nmap={}\narray=[]\noptional=false\nflags=[false]", TypedLoadingSpec::Raw)
    raw.optional.should eq(false)
    raw.flags.should eq([false])
  end

  it "loads inherited and local fields when a subclass has its own constructor" do
    model = TypedLoadingSpec::LabeledNode.new("root", "test")
    restored = FusedTOML.load(model.to_toml, TypedLoadingSpec::LabeledNode)
    {restored.name, restored.label}.should eq({"root", "test"})
    restored.children.should be_empty
  end

  it "validates the entire source and honors the depth limit before mapping" do
    expect_raises(FusedTOML::ParseError) { FusedTOML.load("endpoints=[0]\nunused=?", TypedLoadingSpec::Config) }
    expect_raises(FusedTOML::ParseError) { FusedTOML.load("endpoints=[]\nunused.a.b=1", TypedLoadingSpec::Config, max_depth: 2) }
  end
end
