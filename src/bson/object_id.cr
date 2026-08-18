{% if flag?(:unix) %}
  lib LibPthreadAtFork
    fun pthread_atfork(prepare : ->, parent : ->, child : ->) : LibC::Int
  end
{% end %}

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

    # 12-byte ObjectId stored inline. No heap buffer, and no view into a parent document.
    @bytes : StaticArray(UInt8, 12)

    @@counter = Atomic(UInt32).new(Random::Secure.rand(0x1000000).to_u32)
    # Fixed random bytes in order to have a better ordering.
    @@random_bytes : Bytes = Random::Secure.random_bytes(5)
    @@fork_hook : Bool = install_fork_hook

    # Initialize from a hex string representation.
    def initialize(str : String)
      raise ArgumentError.new("ObjectId string must be exactly 24 hex characters") unless str.bytesize == 24
      ptr = str.to_unsafe
      @bytes = StaticArray(UInt8, 12).new { |i| decode_hex_pair(ptr[i * 2], ptr[i * 2 + 1]) }
    end

    # Initialize from a Byte array.
    def initialize(data : Bytes)
      raise ArgumentError.new("ObjectId bytes must be exactly 12 bytes") unless data.size == 12
      @bytes = StaticArray(UInt8, 12).new { |i| data.unsafe_fetch(i) }
    end

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
      @bytes = StaticArray(UInt8, 12).new(0)

      timestamp = Time.utc.to_unix.to_u32
      IO::ByteFormat::BigEndian.encode(timestamp, @bytes.to_slice[0, 4])

      @@random_bytes.copy_to(@bytes.to_slice[4, 5])

      # Increment first, then wrap to 3 bytes (0x000000..0xFFFFFF).
      counter = (@@counter.add(1) &+ 1) & 0xFFFFFF_u32
      @bytes[9] = (counter >> 16).to_u8!
      @bytes[10] = (counter >> 8).to_u8!
      @bytes[11] = counter.to_u8!
    end

    # Copy of the 12 ObjectId bytes. Safe to keep after this value is gone.
    def data : Bytes
      @bytes.to_slice.clone
    end

    # Inline 12-byte view. Valid only while this ObjectId value is alive.
    def to_slice : Bytes
      @bytes.to_slice
    end

    # Seconds since the Unix epoch, as an unsigned 32-bit value.
    def timestamp : UInt32
      IO::ByteFormat::BigEndian.decode(UInt32, @bytes.to_slice[0, 4])
    end

    # Timestamp field as a UTC `Time`.
    def generation_time : Time
      Time.unix(timestamp.to_i64)
    end

    # Return a string hex representation of the ObjectId.
    def to_s(io : IO) : Nil
      buf = uninitialized UInt8[24]
      to_slice.hexstring(buf.to_unsafe)
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
      to_slice <=> other.to_slice
    end

    # Rebuild the process-unique bytes and the counter. Called after fork.
    def self.reset_process_unique! : Nil
      @@random_bytes = Random::Secure.random_bytes(5)
      @@counter.set(Random::Secure.rand(0x1000000).to_u32)
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

    private def decode_hex_pair(high : UInt8, low : UInt8) : UInt8
      ((hex_nibble(high) << 4) | hex_nibble(low)).to_u8!
    end

    private def self.install_fork_hook : Bool
      {% if flag?(:unix) %}
        # Crystal 1.21 deprecates Process.fork, but a child that keeps running
        # must not reuse the parent process-unique ObjectId bytes.
        LibPthreadAtFork.pthread_atfork(-> { }, -> { }, -> { reset_process_unique! })
      {% end %}
      true
    end

    private def hex_nibble(byte : UInt8) : UInt8
      case byte
      when 0x30_u8..0x39_u8
        byte - 0x30_u8
      when 0x61_u8..0x66_u8
        byte - 0x57_u8
      when 0x41_u8..0x46_u8
        byte - 0x37_u8
      else
        raise ArgumentError.new("ObjectId string must be exactly 24 hex characters")
      end
    end
  end
end
