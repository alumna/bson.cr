struct Slice(T)
  # Serialize to a canonical extended json representation.
  #
  # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
  def to_canonical_extjson(builder : JSON::Builder, subtype : BSON::Binary::SubType? = nil)
    builder.object {
      builder.string("$binary")
      builder.object {
        builder.string("base64")
        builder.string { |io| Base64.strict_encode(self, io) }
        builder.string("subType")
        builder.string { |io|
          v = subtype.try(&.value) || 0_u8
          io << '0' if v < 16
          v.to_s(io, 16)
        }
      }
    }
  end
end
