struct BSON
  # Allocate a BSON instance from a relaxed extended json representation.
  #
  # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
  #
  # ```
  # bson = BSON.from_json(%({
  #   "_id": {
  #     "$oid": "57e193d7a9cc81b4027498b5"
  #   },
  #   "String": "string",
  #   "Int": 42,
  #   "Double": -1.0
  # }))
  # puts bson.to_json # => {"_id":{"$oid":"57e193d7a9cc81b4027498b5"},"String":"string","Int":42,"Double":-1.0}
  # ```
  def self.from_json(json : String)
    self.new(JSON::PullParser.new json)
  end

  # Parse Extended JSON. Returns `nil` when the text is not valid BSON ExtJSON.
  def self.from_json?(json : String) : self?
    from_json(json)
  rescue Error | JSON::ParseException | ArgumentError
    nil
  end

  # ameba:disable Metrics/CyclomaticComplexity
  def to_json(builder : JSON::Builder, *, array = false)
    # [Performance] Inline the blocks to avoid Proc allocations and indirections
    if array
      builder.array { build_json_fields(builder, array: true, canonical: false) }
    else
      builder.object { build_json_fields(builder, array: false, canonical: false) }
    end
  end

  protected def to_canonical_extjson(builder : JSON::Builder, *, array = false)
    # [Performance] Inline the blocks to avoid Proc allocations and indirections
    if array
      builder.array { build_json_fields(builder, array: true, canonical: true) }
    else
      builder.object { build_json_fields(builder, array: false, canonical: true) }
    end
  end

  # [Simplicity] Extracted common logic to avoid code duplication
  private def build_json_fields(builder, array, canonical)
    self.each { |(key, value, code, subtype)|
      builder.string(key) unless array

      if code == Element::Array && value.is_a? BSON
        canonical ? value.to_canonical_extjson(builder, array: true) : value.to_json(builder, array: true)
      elsif !canonical && code == Element::Document && value.is_a? BSON
        value.to_json(builder, array: false)
      elsif code == Element::Binary && value.is_a? Bytes
        value.to_canonical_extjson(builder, subtype)
      elsif !canonical && value.is_a? Int32
        value.to_json(builder)
      elsif !canonical && value.is_a? Int64
        value.to_json(builder)
      elsif !canonical && value.is_a? Float64
        if value.nan? || value.infinite?
          value.to_canonical_extjson(builder)
        else
          value.to_json(builder)
        end
      elsif !canonical && value.is_a? DateTime
        if value.relaxed?
          value.to_relaxed_extjson(builder)
        else
          value.to_canonical_extjson(builder)
        end
      elsif !canonical && value.is_a? Time && value.year >= 1970 && value.year <= 9999
        value.to_relaxed_extjson(builder)
      elsif value.responds_to? :to_canonical_extjson
        value.to_canonical_extjson(builder)
      else
        builder.scalar(nil)
      end
    }
  end

  # Serialize this BSON instance into a canonical extended json representation.
  #
  # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
  # ```
  # bson = BSON.from_json(%({
  #   "Int": 42,
  #   "Double": -1.0
  # }))
  # puts bson.to_canonical_extjson # => {"Int":{"$numberLong":"42"},"Double":{"$numberDouble":"-1.0"}}
  # ```
  def to_canonical_extjson
    io = IO::Memory.new
    builder = JSON::Builder.new io
    builder.start_document
    self.to_canonical_extjson(builder)
    builder.end_document
    io.to_s
  end
end
