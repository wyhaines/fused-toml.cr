module FusedTOML
  # Calendar date without a time or zone.
  record LocalDate, year : Int32, month : Int32, day : Int32

  # Wall-clock time with nanosecond precision.
  record LocalTime, hour : Int32, minute : Int32, second : Int32, nanosecond : Int32

  # Calendar date and wall-clock time without an offset.
  record LocalDateTime, date : LocalDate, time : LocalTime

  # Date and time carrying the UTC designator or its numeric offset.
  record OffsetDateTime, local : LocalDateTime, offset : String

  # Every TOML scalar or container. A document has a table at its root.
  alias Value = String | Int64 | Float64 | Bool | LocalDate | LocalTime | LocalDateTime | OffsetDateTime | Array(Value) | Hash(String, Value)
  alias Table = Hash(String, Value)
end
