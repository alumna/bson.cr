struct UUID
  # Serialize to a canonical extended json representation.
  #
  # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
  def to_canonical_extjson(builder : JSON::Builder)
    builder.object {
      builder.string("$binary")
      builder.object {
        builder.string("base64")
        builder.string { |io| Base64.strict_encode(self.bytes, io) }
        builder.string("subType")
        builder.string("04")
      }
    }
  end
end
