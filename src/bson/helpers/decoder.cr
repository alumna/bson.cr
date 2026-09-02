struct BSON
  private module Decoder
    extend self

    @[AlwaysInline]
    private def check_overflow!(pos, offset, max_pos)
      raise Error.new("Invalid BSON (overflow)") if pos + offset >= max_pos
    end

    protected def check_size!(size, min_size = 0, compare_to = nil)
      if size < min_size || (compare_to && size != compare_to)
        raise Error.new("Invalid BSON (wrong field size: #{size})")
      end
    end

    private def decode_string!(ptr, size = nil, *, skip_checks = false)
      if size
        str = String.new(ptr, size)
        raise Error.new("Invalid string is not null-terminated: #{str}") unless skip_checks || (ptr + size).value == 0x00
      else
        str = String.new(ptr)
      end
      raise Error.new("Invalid utf-8 encoding: #{str}") unless skip_checks || str.valid_encoding?
      str
    end

    # [Performance] Parse regex options directly from raw byte pointer without heap string allocations
    protected def parse_regex_options(ptr : Pointer(UInt8), size : Int) : ::Regex::Options
      BSON::Regex.crystal_options(ptr, size)
    end

    protected def parse_regex_options(opts : String) : ::Regex::Options
      BSON::Regex.crystal_options(opts)
    end

    # Write BSON regex option letters in alphabetical order: i, m, s, u, x.
    protected def write_regex_options(io : IO, options : ::Regex::Options) : Nil
      BSON::Regex.write_letters(io, options)
    end

    # ameba:disable Metrics/CyclomaticComplexity
    protected def decode_field!(pointer, pos, header = nil, max_pos = nil, skip_checks = false)
      if header
        code, key = header
      else
        # Element code
        code = Element.new((pointer + pos).value)
        pos += 1
        # Field name
        key = decode_string!(pointer + pos, skip_checks: skip_checks)
        pos += key.bytesize + 1
      end

      # Switch on element code
      case code
      when Element::Double
        value = (pointer + pos).as(Pointer(Float64)).value
        pos += 8
      when Element::String
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size unless skip_checks
        pos += 4
        check_overflow! pos, str_size, max_pos unless skip_checks
        value = decode_string!(pointer + pos, str_size - 1, skip_checks: skip_checks)
        check_size! str_size, compare_to: value.bytesize + 1 unless skip_checks
        pos += str_size
      when Element::Document
        size = (pointer + pos).as(Pointer(Int32)).value
        check_size! size, 5 unless skip_checks
        check_overflow! pos, size, max_pos unless skip_checks
        value = BSON.view(Bytes.new(pointer + pos, size, read_only: true))
        pos += size
      when Element::Array
        size = (pointer + pos).as(Pointer(Int32)).value
        check_size! size, 5 unless skip_checks
        check_overflow! pos, size, max_pos unless skip_checks
        value = BSON.view(Bytes.new(pointer + pos, size, read_only: true))
        pos += size
      when Element::Binary
        size = (pointer + pos).as(Pointer(Int32)).value
        check_size! size unless skip_checks
        check_overflow! pos, size, max_pos unless skip_checks
        pos += 4
        subtype = Binary::SubType.new((pointer + pos).value)
        pos += 1
        if subtype == Binary::SubType::UUID
          value = UUID.new(Bytes.new(pointer + pos, size, read_only: true))
        elsif subtype == Binary::SubType::Binary_Old
          old_binary_size = (pointer + pos).as(Pointer(Int32)).value
          check_size! old_binary_size, compare_to: size - 4 unless skip_checks
          value = Bytes.new(pointer + pos + 4, old_binary_size, read_only: true)
        else
          value = Bytes.new(pointer + pos, size, read_only: true)
        end
        pos += size
      when Element::Undefined
        value = Undefined.new
      when Element::ObjectId
        oid = ObjectId.new(Bytes.new(pointer + pos, 12, read_only: true))
        value = oid
        pos += 12
      when Element::Boolean
        bool_value = (pointer + pos).value
        if bool_value != 0 && bool_value != 1
          raise Error.new("Invalid BSON bool value: #{bool_value}")
        end
        value = bool_value != 0
        pos += 1
      when Element::DateTime
        value = DateTime.new((pointer + pos).as(Pointer(Int64)).value)
        pos += 8
      when Element::Null
        value = nil
      when Element::Regexp
        # [Performance] Use LibC.strlen instead of manual byte loops
        pattern_size = LibC.strlen(pointer + pos)
        raise Error.new("Invalid Regexp field (string overflow): #{key}") if max_pos && (pos + pattern_size) >= max_pos

        check_size! pattern_size unless skip_checks
        pattern = decode_string!(pointer + pos, pattern_size, skip_checks: skip_checks)
        pos += pattern_size + 1

        opts_size = LibC.strlen(pointer + pos)
        raise Error.new("Invalid Regexp field (string overflow): #{key}") if max_pos && (pos + opts_size) >= max_pos

        check_size! opts_size unless skip_checks
        raw_options = String.new(pointer + pos, opts_size)
        pos += opts_size + 1

        # Keep the pattern as text. Do not compile a Crystal Regex here.
        value = BSON::Regex.new(pattern, raw_options)
      when Element::DBPointer
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size unless skip_checks
        check_overflow! pos, str_size, max_pos unless skip_checks
        pos += 4
        str = decode_string!(pointer + pos, str_size - 1, skip_checks: skip_checks)
        pos += str_size
        oid = ObjectId.new(Bytes.new(pointer + pos, 12, read_only: true))
        pos += 12
        value = DBPointer.new(str, oid)
      when Element::JSCode
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size unless skip_checks
        check_overflow! pos, str_size, max_pos unless skip_checks
        pos += 4
        value = Code.new(decode_string!(pointer + pos, str_size - 1, skip_checks: skip_checks))
        pos += str_size
      when Element::Symbol
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size unless skip_checks
        check_overflow! pos, str_size, max_pos unless skip_checks
        pos += 4
        value = Symbol.new(decode_string!(pointer + pos, str_size - 1, skip_checks: skip_checks))
        pos += str_size
      when Element::JSCodeWithScope
        field_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! field_size, 10 unless skip_checks
        check_overflow! pos, field_size, max_pos unless skip_checks
        pos += 4
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size unless skip_checks
        check_overflow! pos, str_size, max_pos unless skip_checks
        pos += 4
        js_code = decode_string!(pointer + pos, str_size - 1, skip_checks: skip_checks)
        pos += str_size
        doc_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! doc_size, 5 unless skip_checks
        check_overflow! pos, doc_size, max_pos unless skip_checks
        scope = BSON.view(Bytes.new(pointer + pos, doc_size, read_only: true))
        pos += doc_size
        check_size! field_size, str_size + doc_size + 8 unless skip_checks
        value = Code.new(js_code, scope)
      when Element::Int32
        value = (pointer + pos).as(Pointer(Int32)).value
        pos += 4
      when Element::Timestamp
        i = (pointer + pos).as(Pointer(UInt32)).value
        pos += 4
        t = (pointer + pos).as(Pointer(UInt32)).value
        pos += 4
        value = Timestamp.new(t, i)
      when Element::Int64
        value = (pointer + pos).as(Pointer(Int64)).value
        pos += 8
      when Element::Decimal128
        # [Performance] Read Decimal128 directly from raw pointer slice without heap allocation or memory copy
        value = Decimal128.new(Bytes.new(pointer + pos, 16, read_only: true))
        pos += 16
      when Element::MinKey
        value = MinKey.new
      when Element::MaxKey
        value = MaxKey.new
      else
        raise Error.new("Invalid BSON field code.")
      end

      # Return field data and new position
      {pos, {key, value, code, subtype}}
    end

    # Hash/Array from a document buffer. Nested documents and arrays become
    # Hash/Array directly (no BSON.view, no second walk).
    # Empty BSON is 5 bytes → capacity 0 (Crystal Hash initial_capacity 1..7 allocates 8).
    # Do not pre-size from (size-5)//4 on documents: nested child bytes sit in size.
    protected def decode_to_h!(pointer : Pointer(UInt8), size : Int32) : Hash(String, RecursiveValue)
      check_size! size, 5
      hash = Hash(String, RecursiveValue).new(initial_capacity: 0)
      pos = 4

      loop do
        if (pointer + pos).value == 0
          raise Error.new("Invalid BSON size.") if pos != size - 1
          break
        end
        raise Error.new("Invalid BSON size.") if pos >= size

        code = Element.new((pointer + pos).value)
        pos += 1
        # Copy the field name from the C string. String values still check UTF-8.
        key_len = LibC.strlen(pointer + pos)
        raise Error.new("Invalid BSON (string overflow)") if pos + key_len >= size
        key = String.new(pointer + pos, key_len)
        pos += key_len + 1
        pos = store_recursive!(hash, key, pointer, pos, code, size)
      end

      hash
    end

    protected def decode_to_a!(pointer : Pointer(UInt8), size : Int32) : Array(RecursiveValue)
      check_size! size, 5
      payload = size - 5
      cap = 0
      if payload > 0
        upper = payload // 4
        cap = upper <= 8 ? upper : 0
      end
      arr = Array(RecursiveValue).new(initial_capacity: cap)
      pos = 4

      loop do
        if (pointer + pos).value == 0
          raise Error.new("Invalid BSON size.") if pos != size - 1
          break
        end
        raise Error.new("Invalid BSON size.") if pos >= size

        code = Element.new((pointer + pos).value)
        pos += 1
        # Array keys are "0","1",... Discard them. Do not allocate a String.
        key_len = LibC.strlen(pointer + pos)
        raise Error.new("Invalid BSON (string overflow)") if pos + key_len >= size
        pos += key_len + 1
        pos, value = read_recursive_value!(pointer, pos, code, size, "")
        arr << value
      end

      arr
    end

    # Direct Hash assign so the compiler wraps a concrete type, not a returned union.
    # ameba:disable Metrics/CyclomaticComplexity
    private def store_recursive!(hash : Hash(String, RecursiveValue), key, pointer, pos, code, max_pos) : Int32
      case code
      when Element::Document
        nested = (pointer + pos).as(Pointer(Int32)).value
        check_size! nested, 5
        check_overflow! pos, nested, max_pos
        hash[key] = decode_to_h!(pointer + pos, nested)
        pos + nested
      when Element::Array
        nested = (pointer + pos).as(Pointer(Int32)).value
        check_size! nested, 5
        check_overflow! pos, nested, max_pos
        hash[key] = decode_to_a!(pointer + pos, nested)
        pos + nested
      when Element::String
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size
        pos += 4
        check_overflow! pos, str_size, max_pos
        value = decode_string!(pointer + pos, str_size - 1)
        check_size! str_size, compare_to: value.bytesize + 1
        hash[key] = value
        pos + str_size
      when Element::Double
        hash[key] = (pointer + pos).as(Pointer(Float64)).value
        pos + 8
      when Element::Int32
        hash[key] = (pointer + pos).as(Pointer(Int32)).value
        pos + 4
      when Element::Int64
        hash[key] = (pointer + pos).as(Pointer(Int64)).value
        pos + 8
      when Element::Boolean
        bool_value = (pointer + pos).value
        if bool_value != 0 && bool_value != 1
          raise Error.new("Invalid BSON bool value: #{bool_value}")
        end
        hash[key] = bool_value != 0
        pos + 1
      when Element::Null
        hash[key] = nil
        pos
      when Element::ObjectId
        hash[key] = ObjectId.new(Bytes.new(pointer + pos, 12, read_only: true))
        pos + 12
      when Element::DateTime
        hash[key] = DateTime.new((pointer + pos).as(Pointer(Int64)).value)
        pos + 8
      else
        pos, value = read_recursive_value!(pointer, pos, code, max_pos, key)
        hash[key] = value
        pos
      end
    end

    # ameba:disable Metrics/CyclomaticComplexity
    private def read_recursive_value!(pointer, pos, code, max_pos, key) : {Int32, RecursiveValue}
      case code
      when Element::Double
        {(pos + 8), (pointer + pos).as(Pointer(Float64)).value}
      when Element::String
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size
        pos += 4
        check_overflow! pos, str_size, max_pos
        value = decode_string!(pointer + pos, str_size - 1)
        check_size! str_size, compare_to: value.bytesize + 1
        {pos + str_size, value}
      when Element::Document
        nested = (pointer + pos).as(Pointer(Int32)).value
        check_size! nested, 5
        check_overflow! pos, nested, max_pos
        {pos + nested, decode_to_h!(pointer + pos, nested)}
      when Element::Array
        nested = (pointer + pos).as(Pointer(Int32)).value
        check_size! nested, 5
        check_overflow! pos, nested, max_pos
        {pos + nested, decode_to_a!(pointer + pos, nested)}
      when Element::Binary
        size = (pointer + pos).as(Pointer(Int32)).value
        check_size! size
        check_overflow! pos, size, max_pos
        pos += 4
        subtype = Binary::SubType.new((pointer + pos).value)
        pos += 1
        value = if subtype == Binary::SubType::UUID
                  UUID.new(Bytes.new(pointer + pos, size, read_only: true))
                elsif subtype == Binary::SubType::Binary_Old
                  old_binary_size = (pointer + pos).as(Pointer(Int32)).value
                  check_size! old_binary_size, compare_to: size - 4
                  Bytes.new(pointer + pos + 4, old_binary_size, read_only: true)
                else
                  Bytes.new(pointer + pos, size, read_only: true)
                end
        {pos + size, value}
      when Element::Undefined
        {pos, Undefined.new}
      when Element::ObjectId
        {pos + 12, ObjectId.new(Bytes.new(pointer + pos, 12, read_only: true))}
      when Element::Boolean
        bool_value = (pointer + pos).value
        if bool_value != 0 && bool_value != 1
          raise Error.new("Invalid BSON bool value: #{bool_value}")
        end
        {pos + 1, bool_value != 0}
      when Element::DateTime
        {pos + 8, DateTime.new((pointer + pos).as(Pointer(Int64)).value)}
      when Element::Null
        {pos, nil}
      when Element::Regexp
        pattern_size = LibC.strlen(pointer + pos)
        raise Error.new("Invalid Regexp field (string overflow): #{key}") if pos + pattern_size >= max_pos
        check_size! pattern_size
        pattern = decode_string!(pointer + pos, pattern_size)
        pos += pattern_size + 1
        opts_size = LibC.strlen(pointer + pos)
        raise Error.new("Invalid Regexp field (string overflow): #{key}") if pos + opts_size >= max_pos
        check_size! opts_size
        raw_options = String.new(pointer + pos, opts_size)
        {pos + opts_size + 1, BSON::Regex.new(pattern, raw_options)}
      when Element::DBPointer
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size
        check_overflow! pos, str_size, max_pos
        pos += 4
        str = decode_string!(pointer + pos, str_size - 1)
        pos += str_size
        oid = ObjectId.new(Bytes.new(pointer + pos, 12, read_only: true))
        {pos + 12, DBPointer.new(str, oid)}
      when Element::JSCode
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size
        check_overflow! pos, str_size, max_pos
        pos += 4
        value = Code.new(decode_string!(pointer + pos, str_size - 1))
        {pos + str_size, value}
      when Element::Symbol
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size
        check_overflow! pos, str_size, max_pos
        pos += 4
        value = Symbol.new(decode_string!(pointer + pos, str_size - 1))
        {pos + str_size, value}
      when Element::JSCodeWithScope
        field_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! field_size, 10
        check_overflow! pos, field_size, max_pos
        pos += 4
        str_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! str_size
        check_overflow! pos, str_size, max_pos
        pos += 4
        js_code = decode_string!(pointer + pos, str_size - 1)
        pos += str_size
        doc_size = (pointer + pos).as(Pointer(Int32)).value
        check_size! doc_size, 5
        check_overflow! pos, doc_size, max_pos
        scope = BSON.view(Bytes.new(pointer + pos, doc_size, read_only: true))
        pos += doc_size
        check_size! field_size, str_size + doc_size + 8
        {pos, Code.new(js_code, scope)}
      when Element::Int32
        {pos + 4, (pointer + pos).as(Pointer(Int32)).value}
      when Element::Timestamp
        i = (pointer + pos).as(Pointer(UInt32)).value
        t = (pointer + pos + 4).as(Pointer(UInt32)).value
        {pos + 8, Timestamp.new(t, i)}
      when Element::Int64
        {pos + 8, (pointer + pos).as(Pointer(Int64)).value}
      when Element::Decimal128
        {pos + 16, Decimal128.new(Bytes.new(pointer + pos, 16, read_only: true))}
      when Element::MinKey
        {pos, MinKey.new}
      when Element::MaxKey
        {pos, MaxKey.new}
      else
        raise Error.new("Invalid BSON field code.")
      end
    end

    # ameba:disable Metrics/CyclomaticComplexity
    protected def skip_field(code, pointer, pos, *, max_pos = nil)
      case code
      when Element::Double
        pos += 8
      when Element::String
        str_size = (pointer + pos).as(Pointer(Int32)).value
        pos += 4 + str_size
      when Element::Document
        size = (pointer + pos).as(Pointer(Int32)).value
        pos += size
      when Element::Array
        size = (pointer + pos).as(Pointer(Int32)).value
        pos += size
      when Element::Binary
        size = (pointer + pos).as(Pointer(Int32)).value
        pos += 4    # int32 size
        pos += 1    # byte subtype
        pos += size # binary size
      when Element::Undefined
        # size 0
      when Element::ObjectId
        pos += 12
      when Element::Boolean
        pos += 1
      when Element::DateTime
        pos += 8
      when Element::Null
        # size 0
      when Element::Regexp
        # 2 cstrings
        2.times do
          # [Performance] Use LibC.strlen to skip null-terminated strings instantly
          len = LibC.strlen(pointer + pos)
          raise Error.new("Invalid BSON (string overflow)") if max_pos && (pos + len) >= max_pos
          pos += len + 1
        end
      when Element::DBPointer
        str_size = (pointer + pos).as(Pointer(Int32)).value
        pos += 4 + str_size + 12
      when Element::JSCode
        str_size = (pointer + pos).as(Pointer(Int32)).value
        pos += 4 + str_size
      when Element::Symbol
        str_size = (pointer + pos).as(Pointer(Int32)).value
        pos += 4 + str_size
      when Element::JSCodeWithScope
        field_size = (pointer + pos).as(Pointer(Int32)).value
        pos += field_size
      when Element::Int32
        pos += 4
      when Element::Timestamp
        pos += 8
      when Element::Int64
        pos += 8
      when Element::Decimal128
        pos += 16
      when Element::MinKey
        # 0
      when Element::MaxKey
        # 0
      else
        raise Error.new("Invalid BSON field code. Pos: #{pos}")
      end

      # Return new position
      pos
    end
  end
end
