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

      # Parses vector data from a raw byte slice.
      #
      # NOTE: Returns a Vector holding a zero-copy slice view over the underlying buffer memory.
      # Modifying the original byte buffer will modify the vector's content.
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

    # UUID byte order used when encoding or decoding a native `UUID`.
    enum UuidRepresentation
      Standard
      CSharpLegacy
      JavaLegacy
      PythonLegacy
    end

    def initialize(uuid : UUID, representation : UuidRepresentation = UuidRepresentation::Standard)
      bytes = uuid.bytes.to_slice.clone
      case representation
      when .standard?
        @subtype = SubType::UUID
      when .python_legacy?
        @subtype = SubType::UUID_Old
      when .c_sharp_legacy?
        @subtype = SubType::UUID_Old
        swap_csharp_uuid_bytes!(bytes)
      when .java_legacy?
        @subtype = SubType::UUID_Old
        swap_java_uuid_bytes!(bytes)
      else
        raise Exception.new("UUID representation is not specified")
      end
      @data = bytes
    end

    def as_uuid : UUID
      as_uuid(UuidRepresentation::Standard)
    end

    def as_uuid(representation : UuidRepresentation) : UUID
      raise Exception.new("UUID binary must be 16 bytes") unless @data.size == 16
      case representation
      when .standard?
        raise Exception.new("Standard UUID requires subtype 4") unless @subtype.uuid?
        UUID.new(@data)
      when .python_legacy?
        raise Exception.new("Python legacy UUID requires subtype 3") unless @subtype.uuid_old?
        UUID.new(@data)
      when .c_sharp_legacy?
        raise Exception.new("C# legacy UUID requires subtype 3") unless @subtype.uuid_old?
        bytes = @data.clone
        swap_csharp_uuid_bytes!(bytes)
        UUID.new(bytes)
      when .java_legacy?
        raise Exception.new("Java legacy UUID requires subtype 3") unless @subtype.uuid_old?
        bytes = @data.clone
        swap_java_uuid_bytes!(bytes)
        UUID.new(bytes)
      else
        raise Exception.new("UUID representation is not specified")
      end
    end

    def to_vector : Vector
      raise Exception.new("Not a vector") unless subtype.vector?
      Vector.from_binary_data(@data)
    end

    def self.from_vector(vector : Indexable(Float32)) : self
      payload = Bytes.new(2 + vector.size * 4)
      payload[0] = Vector::DataType::Float32.value
      payload[1] = 0_u8
      vector.each_with_index do |val, i|
        IO::ByteFormat::LittleEndian.encode(val, payload[2 + i * 4, 4])
      end
      new(SubType::Vector, payload)
    end

    def self.from_vector(vector : Indexable(Float64)) : self
      payload = Bytes.new(2 + vector.size * 4)
      payload[0] = Vector::DataType::Float32.value
      payload[1] = 0_u8
      vector.each_with_index do |val, i|
        f32_val = val.to_f32!
        if val.finite? && f32_val.infinite?
          raise Exception.new("Float64 value #{val} overflows Float32 range during vector conversion")
        end
        IO::ByteFormat::LittleEndian.encode(f32_val, payload[2 + i * 4, 4])
      end
      new(SubType::Vector, payload)
    end

    def self.from_vector(vector : Indexable(Int8)) : self
      payload = Bytes.new(2 + vector.size)
      payload[0] = Vector::DataType::Int8.value
      payload[1] = 0_u8
      vector.each_with_index do |val, i|
        payload[2 + i] = val.to_u8!
      end
      new(SubType::Vector, payload)
    end

    def self.from_vector(vector : Indexable(Int32)) : self
      payload = Bytes.new(2 + vector.size)
      payload[0] = Vector::DataType::Int8.value
      payload[1] = 0_u8
      vector.each_with_index do |val, i|
        raise Exception.new("Value #{val} out of bounds for INT8") unless -128 <= val <= 127
        payload[2 + i] = val.to_u8!
      end
      new(SubType::Vector, payload)
    end

    def self.from_packed_bit_vector(vector : Indexable(UInt8), padding : Int = 0) : self
      raise Exception.new("Invalid PACKED_BIT vector: padding must be between 0 and 7") unless 0 <= padding <= 7
      check_packed_bit_ignored_bits!(vector, padding)
      payload = Bytes.new(2 + vector.size)
      payload[0] = Vector::DataType::PackedBit.value
      payload[1] = padding.to_u8!
      vector.each_with_index do |val, i|
        payload[2 + i] = val
      end
      new(SubType::Vector, payload)
    end

    def self.from_packed_bit_vector(vector : Indexable(Int32), padding : Int = 0) : self
      raise Exception.new("Invalid PACKED_BIT vector: padding must be between 0 and 7") unless 0 <= padding <= 7
      check_packed_bit_ignored_bits!(vector, padding)
      payload = Bytes.new(2 + vector.size)
      payload[0] = Vector::DataType::PackedBit.value
      payload[1] = padding.to_u8!
      vector.each_with_index do |val, i|
        raise Exception.new("Value #{val} out of bounds for PACKED_BIT") unless 0 <= val <= 255
        payload[2 + i] = val.to_u8!
      end
      new(SubType::Vector, payload)
    end

    private def self.check_packed_bit_ignored_bits!(vector : Indexable, padding : Int) : Nil
      return if padding == 0
      raise Exception.new("Invalid PACKED_BIT vector: data cannot be empty if padding > 0") if vector.empty?
      last = vector[vector.size - 1].to_u8!
      mask = (1_u8 << padding) - 1_u8
      if (last & mask) != 0
        raise Exception.new("Invalid PACKED_BIT vector: ignored bits must be zero")
      end
    end

    private def swap_csharp_uuid_bytes!(bytes : Bytes) : Nil
      bytes[0], bytes[3] = bytes[3], bytes[0]
      bytes[1], bytes[2] = bytes[2], bytes[1]
      bytes[4], bytes[5] = bytes[5], bytes[4]
      bytes[6], bytes[7] = bytes[7], bytes[6]
    end

    private def swap_java_uuid_bytes!(bytes : Bytes) : Nil
      4.times do |i|
        bytes[i], bytes[7 - i] = bytes[7 - i], bytes[i]
        bytes[8 + i], bytes[15 - i] = bytes[15 - i], bytes[8 + i]
      end
    end
  end
end
