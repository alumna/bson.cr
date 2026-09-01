struct BSON
  # Incremental BSON writer. Cryomongo can use this to build a document in one pass.
  class Builder
    getter io : IO::Memory

    # Pre-allocated static string representation for small array/field integer indices (0..127) to avoid heap allocations
    STATIC_INDICES = Array(String).new(128) { |i| i.to_s }

    def initialize(@io : IO::Memory = IO::Memory.new); end

    private def field(code : Element, key : String)
      raise ArgumentError.new("BSON keys cannot contain a null byte") if key.includes?('\0')
      # [Performance] Use write_byte instead of write_bytes for 1-byte primitives
      @io.write_byte code.value
      @io << key
      @io.write_byte 0x00_u8
    end

    def []=(key : String, value : Float64)
      field(:double, key)
      @io.write_bytes value, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : Float32)
      field(:double, key)
      @io.write_bytes value.to_f64, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : String)
      field(:string, key)
      @io.write_bytes value.bytesize + 1, IO::ByteFormat::LittleEndian
      @io << value
      @io.write_byte 0x00_u8
    end

    def []=(key : String, value : BSON)
      field(:document, key)
      @io.write value.data
    end

    def []=(key : String, value : BSON::Serializable)
      field(:document, key)
      @io.write value.to_bson.data
    end

    def []=(key : String, value : NamedTuple)
      field(:document, key)
      @io.write BSON.new(value).data
    end

    def []=(key : String, value : Hash)
      document(key) do
        value.each { |k, v|
          self[k.to_s] = v
        }
      end
    end

    def append_array(key : String, value : BSON)
      field(:array, key)
      @io.write value.data
    end

    # Nested document in this IO. Yields self. Empty nested size is 5.
    def document(key : String, &) : Nil
      size_pos = start_nested(:document, key)
      yield self
      close_nested(size_pos)
    end

    # Nested array in this IO. Yields self. Empty nested size is 5.
    def array(key : String, &) : Nil
      size_pos = start_nested(:array, key)
      yield self
      close_nested(size_pos)
    end

    def []=(key : String, value : Array)
      array(key) do
        value.each_with_index { |item, index|
          # [Performance] Use pre-allocated static index strings for common indices (0..127) to avoid heap allocations
          str_index = index < 128 ? STATIC_INDICES.unsafe_fetch(index) : index.to_s
          if item.responds_to? :to_bson
            self[str_index] = item.to_bson
          else
            self[str_index] = item
          end
        }
      end
    end

    def []=(key : String, value : Binary)
      field(:binary, key)
      if value.subtype.binary_old?
        @io.write_bytes value.data.size + 4, IO::ByteFormat::LittleEndian
        @io.write_byte value.subtype.value
        @io.write_bytes value.data.size, IO::ByteFormat::LittleEndian
      else
        @io.write_bytes value.data.size, IO::ByteFormat::LittleEndian
        @io.write_byte value.subtype.value
      end
      @io.write value.data
    end

    def []=(key : String, value : Bytes)
      self.[key] = Binary.new(:generic, value)
    end

    def []=(key : String, value : UUID)
      self.[key] = Binary.new(value)
    end

    def []=(key : String, value : ObjectId)
      field(:object_id, key)
      @io.write value.to_slice
    end

    def []=(key : String, value : Bool)
      field(:boolean, key)
      # [Simplicity] Rename to avoid shadowing the method parameter
      byte_value = value ? 0x01_u8 : 0x00_u8
      @io.write_byte byte_value
    end

    def []=(key : String, value : Time)
      field(:date_time, key)
      @io.write_bytes value.to_unix_ms, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : Nil)
      field(:null, key)
    end

    def []=(key : String, value : DateTime)
      field(:date_time, key)
      @io.write_bytes value.milliseconds, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : BSON::Regex)
      field(:regexp, key)
      @io << value.pattern
      @io.write_byte 0x00_u8
      @io << value.options
      @io.write_byte 0x00_u8
    end

    def []=(key : String, value : ::Regex)
      self.[key] = BSON::Regex.new(value)
    end

    def []=(key : String, value : Int8)
      field(:int32, key)
      @io.write_bytes value.to_i32, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : UInt8)
      field(:int32, key)
      @io.write_bytes value.to_i32, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : Int16)
      field(:int32, key)
      @io.write_bytes value.to_i32, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : UInt16)
      field(:int32, key)
      @io.write_bytes value.to_i32, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : Int32)
      field(:int32, key)
      @io.write_bytes value, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : UInt32)
      field(:int64, key)
      @io.write_bytes value.to_i64, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : Int64)
      field(:int64, key)
      @io.write_bytes value, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : Decimal128)
      field(:decimal128, key)
      value.to_io(@io)
    end

    def []=(key : String, value : Code)
      if scope = value.scope
        field(:js_code_with_scope, key)
        total_size = 8 + value.code.bytesize + 1 + scope.data.size
        @io.write_bytes total_size, IO::ByteFormat::LittleEndian
        @io.write_bytes value.code.bytesize + 1, IO::ByteFormat::LittleEndian
        @io << value.code
        @io.write_byte 0x00_u8
        @io.write scope.data
      else
        field(:js_code, key)
        @io.write_bytes value.code.bytesize + 1, IO::ByteFormat::LittleEndian
        @io << value.code
        @io.write_byte 0x00_u8
      end
    end

    def []=(key : String, value : Symbol)
      field(:symbol, key)
      @io.write_bytes value.data.bytesize + 1, IO::ByteFormat::LittleEndian
      @io << value.data
      @io.write_byte 0x00_u8
    end

    def []=(key : String, value : Timestamp)
      field(:timestamp, key)
      @io.write_bytes value.i, IO::ByteFormat::LittleEndian
      @io.write_bytes value.t, IO::ByteFormat::LittleEndian
    end

    def []=(key : String, value : DBPointer)
      field(:db_pointer, key)
      @io.write_bytes value.data.bytesize + 1, IO::ByteFormat::LittleEndian
      @io << value.data
      @io.write_byte 0x00_u8
      @io.write value.oid.to_slice
    end

    def []=(key : String, value : Undefined)
      field(:undefined, key)
    end

    def []=(key : String, value : MinKey)
      field(:min_key, key)
    end

    def []=(key : String, value : MaxKey)
      field(:max_key, key)
    end

    def to_bson
      fields = @io.to_slice
      size = 5 + fields.size
      data = Bytes.new(size)
      IO::ByteFormat::LittleEndian.encode(size, data[0, 4])
      data[4, fields.size].copy_from(fields)
      data
    end

    # Type + key + NUL, then a 4-byte little-endian Int32 placeholder (0).
    private def start_nested(code : Element, key : String) : Int32
      field(code, key)
      size_pos = @io.pos
      @io.write_bytes 0_i32, IO::ByteFormat::LittleEndian
      size_pos
    end

    # Trailing 0x00, then patch size (placeholder through NUL, inclusive) and seek to the end.
    private def close_nested(size_pos : Int32) : Nil
      @io.write_byte 0x00_u8
      end_pos = @io.pos
      @io.seek(size_pos)
      @io.write_bytes (end_pos - size_pos).to_i32, IO::ByteFormat::LittleEndian
      @io.seek(end_pos)
    end
  end
end
