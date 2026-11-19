require "./fused_toml/value"
require "./fused_toml/error"
require "./fused_toml/parser"

module FusedTOML
  # Reads a complete TOML 1.1 document into a root table.
  def self.load(source : String, *, max_depth : Int32 = 128) : Table
    Parser.new(source, max_depth).parse
  end
end
