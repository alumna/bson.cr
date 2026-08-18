struct BSON
  # BSON UTC datetime: milliseconds since the Unix epoch, as a signed 64-bit integer.
  #
  # Crystal `Time` cannot store every BSON datetime (for example year 10000).
  # This type keeps the full range. Use `#to_time` or `#to_time?` when you need `Time`.
  struct DateTime
    include Comparable(DateTime)

    # Inclusive `Time.unix_ms` range that Crystal can store.
    MIN_TIME_MS = -62_135_596_800_000_i64
    MAX_TIME_MS = 253_402_300_799_999_i64

    getter milliseconds : Int64

    def initialize(@milliseconds : Int64)
    end

    def initialize(time : Time)
      @milliseconds = time.to_unix_ms
    end

    def to_unix_ms : Int64
      @milliseconds
    end

    # `true` when Crystal `Time` can store this value.
    def in_time_range? : Bool
      MIN_TIME_MS <= @milliseconds <= MAX_TIME_MS
    end

    # Convert to `Time`. Raises when the value is outside the Crystal range.
    def to_time : Time
      Time.unix_ms(@milliseconds)
    end

    # Convert to `Time`, or `nil` when the value is outside the Crystal range.
    def to_time? : Time?
      return nil unless in_time_range?
      Time.unix_ms(@milliseconds)
    end

    # Relaxed Extended JSON can use an ISO-8601 string for years 1970 through 9999.
    def relaxed? : Bool
      0 <= @milliseconds <= MAX_TIME_MS
    end

    def to_json(builder : JSON::Builder)
      to_canonical_extjson(builder)
    end

    # Serialize to a canonical extended json representation.
    #
    # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
    def to_canonical_extjson(builder : JSON::Builder)
      builder.object {
        builder.string("$date")
        builder.object {
          builder.string("$numberLong")
          builder.string { |io| @milliseconds.to_s(io) }
        }
      }
    end

    # Serialize to a relaxed extended json representation.
    #
    # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
    def to_relaxed_extjson(builder : JSON::Builder)
      if relaxed?
        if time = to_time?
          time.to_relaxed_extjson(builder)
          return
        end
      end
      to_canonical_extjson(builder)
    end

    def <=>(other : DateTime)
      @milliseconds <=> other.milliseconds
    end

    def ==(other : Time) : Bool
      @milliseconds == other.to_unix_ms
    end
  end
end
