require "./fused_toml/value"
require "./fused_toml/error"
require "./fused_toml/limits"
require "./fused_toml/input"
require "./fused_toml/parser"
require "./fused_toml/writer"
require "./fused_toml/serializable"
require "./fused_toml/decoder"

module FusedTOML
  # Reads a complete TOML 1.1 document into a root table.
  def self.load(source : String | IO, *, max_depth : Int32 = 128, limits : Limits = Limits::DEFAULT) : Table
    check_max_depth(max_depth)
    Parser.new(Input.document(source, limits.max_document_bytes), max_depth, limits).parse
  end

  # Validates a complete document, then maps its root table to T.
  def self.load(source : String | IO, type : T.class, *, max_depth : Int32 = 128, limits : Limits = Limits::DEFAULT) : T forall T
    Decoder.new.read(load(source, max_depth: max_depth, limits: limits), type)
  end

  # Encodes the table as a deterministic TOML 1.1 document.
  def self.dump(table : Table, *, max_depth : Int32 = 128) : String
    String.build { |io| dump(table, io, max_depth: max_depth) }
  end

  # Writes the document to a borrowed IO. An error can leave a prefix written.
  def self.dump(table : Table, io : IO, *, max_depth : Int32 = 128) : Nil
    check_max_depth(max_depth)
    Writer.new(io, max_depth).write(table)
  end

  private def self.check_max_depth(depth)
    raise ArgumentError.new("max_depth must be between 1 and 256") unless (1..256).includes?(depth)
  end
end
