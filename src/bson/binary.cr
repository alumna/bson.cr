require "uuid"

struct BSON
  # Binary data.
  struct Binary
    # BSON binary values have a subtype. This is used to indicate what kind of data is in the byte array.
    # Subtypes from zero to 127 are predefined or reserved. Subtypes from 128-255 are user-defined.
    enum SubType : UInt8
      Generic              = 0x00
      Function             = 0x01
      Binary_Old           = 0x02
      UUID_Old             = 0x03
      UUID                 = 0x04
      MD5                  = 0x05
      EncryptedBSON        = 0x06
      CompressedBSONColumn = 0x07
      Sensitive            = 0x08
      Vector               = 0x09
      UserDefined          = 0x80
    end

    struct Vector
      enum DataType : UInt8
        Int8      = 0x03
        Float32   = 0x27
        PackedBit = 0x10
      end

      getter dtype : DataType
      getter padding : UInt8
      getter data : Bytes

      def initialize(@dtype : DataType, @data : Bytes, @padding : UInt8 = 0_u8)
        validate!
      end

      private def validate!
        case @dtype
        when .float32?
          raise Exception.new("Invalid FLOAT32 vector: padding must be 0") unless @padding == 0
          raise Exception.new("Invalid FLOAT32 vector: data length must be a multiple of 4 bytes") unless @data.size % 4 == 0
        when .int8?
          raise Exception.new("Invalid INT8 vector: padding must be 0") unless @padding == 0
        when .packed_bit?
          raise Exception.new("Invalid PACKED_BIT vector: padding must be between 0 and 7") if @padding > 7
          if @padding > 0
            raise Exception.new("Invalid PACKED_BIT vector: data cannot be empty if padding > 0") if @data.empty?
            # Enforce that ignored bits (least-significant bits) are zero
            mask = (1_u8 << @padding) - 1_u8
            if (@data.last & mask) != 0
              raise Exception.new("Invalid PACKED_BIT vector: ignored bits must be zero")
            end
          end
        end
      end

      def to_binary_data : Bytes
        result = Bytes.new(2 + @data.size)
        result[0] = @dtype.value
        result[1] = @padding
        @data.copy_to(result[2..])
        result
      end

      def self.from_binary_data(data : Bytes) : self
        raise Exception.new("Vector data too short") if data.size < 2
        dtype = DataType.from_value?(data[0]) || raise Exception.new("Unknown vector dtype: #{data[0]}")
        padding = data[1]
        Vector.new(dtype, data[2..], padding)
      end

      # Returns a zero-copy Slice over the underlying bytes.
      # Assumes the executing system uses Little Endian (standard for BSON targets like x86/ARM).
      def as_float32 : Slice(Float32)
        raise Exception.new("Not a FLOAT32 vector") unless @dtype.float32?
        @data.unsafe_slice_of(Float32)
      end

      # Returns a zero-copy Slice over the underlying bytes.
      def as_int8 : Slice(Int8)
        raise Exception.new("Not an INT8 vector") unless @dtype.int8?
        @data.unsafe_slice_of(Int8)
      end

      # Directly returns the underlying Bytes slice since PackedBit maps cleanly to UInt8 arrays.
      def as_packed_bit : Bytes
        raise Exception.new("Not a PACKED_BIT vector") unless @dtype.packed_bit?
        @data
      end
    end

    getter subtype, data

    def initialize(@subtype : SubType, data : Bytes)
      @data = data
    end

    def initialize(uuid : UUID)
      @subtype = SubType::UUID
      @data = uuid.bytes.to_slice.clone
    end

    def to_vector : Vector
      raise Exception.new("Not a vector") unless subtype.vector?
      Vector.from_binary_data(@data)
    end

    def self.from_vector(vector : Indexable(Float32) | Indexable(Float64)) : self
      payload = Bytes.new(2 + vector.size * 4)
      payload[0] = Vector::DataType::Float32.value
      payload[1] = 0_u8
      # IO::Memory wrap allows us to safely guarantee Little Endian format conversion
      io = IO::Memory.new(payload[2..])
      vector.each { |val| io.write_bytes(val.to_f32!, IO::ByteFormat::LittleEndian) }
      new(SubType::Vector, payload)
    end

    def self.from_vector(vector : Indexable(Int8) | Indexable(Int32)) : self
      payload = Bytes.new(2 + vector.size)
      payload[0] = Vector::DataType::Int8.value
      payload[1] = 0_u8
      vector.each_with_index do |val, i|
        raise Exception.new("Value #{val} out of bounds for INT8") unless -128 <= val <= 127
        payload[2 + i] = val.to_u8!
      end
      new(SubType::Vector, payload)
    end

    def self.from_packed_bit_vector(vector : Indexable(UInt8) | Indexable(Int32), padding : Int = 0) : self
      raise Exception.new("Invalid PACKED_BIT vector: padding must be between 0 and 7") unless 0 <= padding <= 7
      payload = Bytes.new(2 + vector.size)
      payload[0] = Vector::DataType::PackedBit.value
      payload[1] = padding.to_u8!
      vector.each_with_index do |val, i|
        raise Exception.new("Value #{val} out of bounds for PACKED_BIT") unless 0 <= val <= 255
        payload[2 + i] = val.to_u8!
      end
      new(SubType::Vector, payload)
    end
  end
end
