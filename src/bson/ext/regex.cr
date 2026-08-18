class Regex
  def ==(other : BSON::Regex) : Bool
    other == self
  end

  # Serialize to a canonical extended json representation.
  #
  # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
  def to_canonical_extjson(builder : JSON::Builder)
    builder.object {
      builder.string("$regularExpression")
      builder.object {
        builder.string("pattern")
        builder.string(self.source)
        builder.string("options")
        builder.string do |io|
          BSON::Regex.write_letters(io, self.options)
        end
      }
    }
  end
end
