module FusedTOML
  # Calendar date without a time or zone.
  record LocalDate, year : Int32, month : Int32, day : Int32 do
    def valid? : Bool
      return false unless 0 <= year <= 9999 && 1 <= month <= 12

      # Time starts at year 1. Year 400 has the same Gregorian calendar as year 0.
      1 <= day <= Time.days_in_month(year.zero? ? 400 : year, month)
    end
  end

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
