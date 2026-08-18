struct BSON
  private module Decoder
    extend self

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
