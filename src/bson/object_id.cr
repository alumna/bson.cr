struct BSON
  # Unique object identifier.
  #
  # See: dochub.mongodb.org/core/objectids
  struct ObjectId
    include Comparable(ObjectId)

    # This converter can be used to serialize the ObjectId to a String value.
    #
    # ```
    # @[JSON::Field(converter: BSON::ObjectId::StringConverter)]
    # property _id : BSON::ObjectId
    # ```
    module StringConverter
      def self.from_json(pull : JSON::PullParser) : BSON::ObjectId
        BSON::ObjectId.new pull.read_string
      end

      def self.to_json(value : BSON::ObjectId, builder : JSON::Builder)
        builder.string value.to_s
      end
    end

    getter data : Bytes

    @@counter : Int32 = rand(0x1000000)
    @@mutex = Sync::Mutex.new
    # Fixed random bytes in order to have a better ordering.
    @@random_bytes : Bytes = Random::Secure.random_bytes(5)

    # Initialize from a hex string representation.
    def initialize(str : String)
      raise ArgumentError.new("ObjectId string must be exactly 24 hex characters") unless str.bytesize == 24
      @data = str.hexbytes
    end

    # Initialize from a Byte array.
    def initialize(@data : Bytes); end

    # Initialize from a JSON object.
    def self.new(pull : JSON::PullParser)
      pull.read_begin_object
      key = pull.read_object_key
      raise "ObjectID key must be $oid but is #{key}." if key != "$oid"
      value = BSON::ObjectId.new pull.read_string
      pull.read_end_object
      value
    end

    # Create a random ObjectId.
    def initialize
      # [Performance] Avoid IO::Memory and heap allocations by writing directly to a slice
      @data = Bytes.new(12)

      timestamp = Time.utc.to_unix.to_u32
      IO::ByteFormat::BigEndian.encode(timestamp, @data[0, 4])

      @@random_bytes.copy_to(@data[4, 5])

      counter = @@mutex.synchronize {
        # [Correctness] Use 0x1000000 to wrap correctly at 3 bytes max (16777215)
        @@counter = (@@counter + 1) % 0x1000000
      }

      @data[9] = (counter >> 16).to_u8!
      @data[10] = (counter >> 8).to_u8!
      @data[11] = counter.to_u8!
    end

    # Return a string hex representation of the ObjectId.
    def to_s(io : IO) : Nil
      buf = uninitialized UInt8[24]
      @data.hexstring(buf.to_unsafe)
      io.write_string(buf.to_slice)
    end

    def to_json(builder : JSON::Builder)
      to_canonical_extjson(builder)
    end

    # Serialize to a canonical extended json representation.
    #
    # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
    def to_canonical_extjson(builder : JSON::Builder)
      builder.object {
        builder.string("$oid")
        builder.string { |io| self.to_s(io) }
      }
    end

    def <=>(other : ObjectId)
      @data <=> other.data
    end

    # Validate that a provided string is a well formated ObjectId.
    def self.validate(id : String) : Bool
      return false unless id.bytesize == 24
      id.each_byte do |b|
        return false unless (0x30_u8 <= b <= 0x39_u8) || # '0'-'9'
                            (0x61_u8 <= b <= 0x66_u8) || # 'a'-'f'
                            (0x41_u8 <= b <= 0x46_u8)    # 'A'-'F'
      end
      true
    end
  end
end
