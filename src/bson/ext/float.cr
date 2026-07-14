struct Float64
  # Serialize to a canonical extended json representation.
  #
  # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
  def to_canonical_extjson(builder : JSON::Builder)
    builder.object {
      builder.string("$numberDouble")
      builder.string do |io|
        # [Performance] Write directly to IO while converting 'e' to 'E' without string allocations
        str = self.to_s
        str.each_char do |c|
          io << (c == 'e' ? 'E' : c)
        end
      end
    }
  end
end
