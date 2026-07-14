struct Time
  # Serialize to a canonical extended json representation.
  #
  # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
  def to_canonical_extjson(builder : JSON::Builder)
    builder.object {
      builder.string("$date")
      builder.object {
        builder.string("$numberLong")
        builder.string { |io| self.to_unix_ms.to_s(io) }
      }
    }
  end

  # Serialize to a canonical extended json representation.
  #
  # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
  def to_relaxed_extjson(builder : JSON::Builder)
    builder.object {
      builder.string("$date")
      builder.string do |io|
        if millisecond == 0
          self.to_rfc3339(fraction_digits: 0, io: io)
        else
          self.to_rfc3339(fraction_digits: 3, io: io)
        end
      end
    }
  end
end
