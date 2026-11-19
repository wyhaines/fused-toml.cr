require "fused_toml"

module ReadOnlyConverter
  def self.from_toml(value : FusedTOML::Value) : Time::Span
    value.as(Int64).seconds
  end
end

struct ReadOnlyModel
  include FusedTOML::Serializable

  @[FusedTOML::Field(key: "job.timeout", converter: ReadOnlyConverter)]
  getter duration : Time::Span
end

module InvalidConverter
  def self.to_toml(value : Time::Span) : Time::Span
    value
  end
end

struct InvalidResult
  include FusedTOML::Serializable

  @[FusedTOML::Field(key: "wait", converter: InvalidConverter)]
  getter duration = 1.second

  def initialize
  end
end

struct DuplicateKey
  include FusedTOML::Serializable

  @[FusedTOML::Field(key: "port")]
  getter listen = 80
  getter port = 443

  def initialize
  end
end

struct AmbiguousField
  include FusedTOML::Serializable

  getter port : String | Int32 = 443

  def initialize
  end
end

struct FalseKey
  include FusedTOML::Serializable

  @[FusedTOML::Field(key: false)]
  getter port = 80
end

struct NilKey
  include FusedTOML::Serializable

  @[FusedTOML::Field(key: nil)]
  getter port = 80

  def initialize
  end
end
