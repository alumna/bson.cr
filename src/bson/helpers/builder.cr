struct BSON
  private class Builder
    getter io : IO::Memory

    def initialize(@io : IO::Memory = IO::Memory.new); end

    private def field(code : Element, key : String)
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
      field(:document, key)
      @io.write BSON.new(value).data
    end

    def append_array(key : String, value : BSON)
      field(:array, key)
      @io.write value.data
    end

    def []=(key : String, value : Array)
      array_builder = Builder.new
      value.each_with_index { |item, index|
        # [Performance] Avoid string interpolation overhead
        str_index = index.to_s
        if item.responds_to? :to_bson
          array_builder[str_index] = item.to_bson
        else
          array_builder[str_index] = item
        end
      }
      field(:array, key)
      # [Performance] Directly use bytes to avoid unnecessary instantiation and copy
      @io.write array_builder.to_bson
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
      @io.write value.data
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

    def []=(key : String, value : Regex)
      field(:regexp, key)
      @io << value.source
      @io.write_byte 0x00_u8
      # [Performance] Write option chars directly to IO instead of a new String allocation
      @io.write_byte 'i'.ord.to_u8! if value.options.includes? :ignore_case
      @io.write_byte 'm'.ord.to_u8! if value.options.includes? :multiline
      @io.write_byte 'x'.ord.to_u8! if value.options.includes? :extended
      @io.write_byte 'u'.ord.to_u8! if value.options.includes? :utf_8
      @io.write_byte 0x00_u8
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

    def []=(key : String, value : BigDecimal)
      field(:decimal128, key)
      @io.write Decimal128.new(value).bytes
    end

    def []=(key : String, value : Decimal128)
      field(:decimal128, key)
      @io.write value.bytes
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
      @io.write value.oid.data
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
      IO::ByteFormat::LittleEndian.encode(size, data[0...4])
      data[4...-1].copy_from(fields)
      data
    end
  end
end
