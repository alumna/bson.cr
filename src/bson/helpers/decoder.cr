struct BSON
  private module Decoder
    extend self

    private def check_overflow!(pos, offset, max_pos)
      raise "Invalid BSON (overflow)" if pos + offset >= max_pos
    end

    protected def check_size!(size, min_size = 0, compare_to = nil)
      if size < min_size || (compare_to && size != compare_to)
        raise "Invalid BSON (wrong field size: #{size})"
      end
    end

    private def decode_string!(ptr, size = nil, *, skip_checks = false)
      if size
        str = String.new(ptr, size)
        raise "Invalid string is not null-terminated: #{str}" unless skip_checks || (ptr + size).value == 0x00
      else
        str = String.new(ptr)
      end
      raise "Invalid utf-8 encoding: #{str}" unless skip_checks || str.valid_encoding?
      str
    end

    # [Performance] Parse regex options directly from raw byte pointer without heap string allocations
    protected def parse_regex_options(ptr : Pointer(UInt8), size : Int) : Regex::Options
      modifiers = Regex::Options::None
      size.times do |i|
        case (ptr + i).value
        when 0x69_u8 # 'i'
          modifiers |= Regex::Options::IGNORE_CASE
        when 0x6d_u8, 0x73_u8 # 'm', 's'
          modifiers |= Regex::Options::MULTILINE
        when 0x78_u8 # 'x'
          modifiers |= Regex::Options::EXTENDED
        when 0x75_u8 # 'u'
          modifiers |= Regex::Options::UTF_8
        end
      end
      modifiers
    end

    protected def parse_regex_options(opts : String) : Regex::Options
      parse_regex_options(opts.to_unsafe, opts.bytesize)
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
        value = BSON.new(Bytes.new(pointer + pos, size))
        pos += size
      when Element::Array
        size = (pointer + pos).as(Pointer(Int32)).value
        check_size! size, 5 unless skip_checks
        check_overflow! pos, size, max_pos unless skip_checks
        value = BSON.new(Bytes.new(pointer + pos, size))
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
          raise "Invalid BSON bool value: #{bool_value}"
        end
        value = bool_value != 0
        pos += 1
      when Element::DateTime
        value = Time.unix_ms((pointer + pos).as(Pointer(Int64)).value)
        pos += 8
      when Element::Null
        value = nil
      when Element::Regexp
        # [Performance] Use LibC.strlen instead of manual byte loops
        pattern_size = LibC.strlen(pointer + pos)
        raise "Invalid Regexp field (string overflow): #{key}" if max_pos && (pos + pattern_size) >= max_pos

        check_size! pattern_size unless skip_checks
        pattern = decode_string!(pointer + pos, pattern_size, skip_checks: skip_checks)
        pos += pattern_size + 1

        opts_size = LibC.strlen(pointer + pos)
        raise "Invalid Regexp field (string overflow): #{key}" if max_pos && (pos + opts_size) >= max_pos

        check_size! opts_size unless skip_checks
        regex_options = parse_regex_options(pointer + pos, opts_size)
        pos += opts_size + 1

        value = Regex.new(pattern, regex_options)
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
        scope = BSON.new(Bytes.new(pointer + pos, doc_size))
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
        raise "Invalid BSON field code."
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
          raise "Invalid BSON (string overflow)" if max_pos && (pos + len) >= max_pos
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
        raise "Invalid BSON field code. Pos: #{pos}"
      end

      # Return new position
      pos
    end

    protected def decode_json_key(kind : JSON::PullParser::Kind, key : String, builder : Builder, pull : JSON::PullParser)
      case kind
      when .null?
        builder[key] = pull.read_null
      when .bool?
        builder[key] = pull.read_bool
      when .int?
        builder[key] = pull.read_int
      when .float?
        builder[key] = pull.read_float
      when .string?
        builder[key] = pull.read_string
      when .begin_array?
        builder.append_array(key, BSON.new(pull))
      when .begin_object?
        pull.read_begin_object
        if pull.kind.end_object?
          # [Performance] Directly create an empty BSON document without allocating a Builder and intermediate buffers
          builder[key] = BSON.new
        else
          inner_key = pull.read_object_key
          raise "Bad document key" if inner_key.includes?('\u0000')
          self.decode_json_object(inner_key, kind, key, builder, pull)
        end
        pull.read_end_object
      else
        # Ignore
      end
    end

    # ameba:disable Metrics/CyclomaticComplexity
    protected def decode_json_object(inner_key : String, kind : JSON::PullParser::Kind, key : String, builder : Builder, pull : JSON::PullParser)
      case inner_key
      when "$oid"
        raise "Bad $oid" unless pull.kind.string?
        builder[key] = ObjectId.new(pull.read_string)
        raise "Bad $oid" unless pull.kind.end_object?
      when "$symbol"
        raise "Bad $symbol" unless pull.kind.string?
        builder[key] = Symbol.new(pull.read_string)
        raise "Bad $symbol" unless pull.kind.end_object?
      when "$numberInt"
        raise "Bad $numberInt" unless pull.kind.string?
        builder[key] = pull.read_string.to_i32
        raise "Bad $numberInt" unless pull.kind.end_object?
      when "$numberLong"
        raise "Bad $numberLong" unless pull.kind.string?
        builder[key] = pull.read_string.to_i64
        raise "Bad $numberLong" unless pull.kind.end_object?
      when "$numberDouble"
        raise "Bad $numberDouble" unless pull.kind.string?
        double_str = pull.read_string
        builder[key] = case double_str
                       when "Infinity"  then Float64::INFINITY
                       when "-Infinity" then -Float64::INFINITY
                       when "NaN"       then Float64::NAN
                       else                  double_str.to_f64
                       end
        raise "Bad $numberDouble" unless pull.kind.end_object?
      when "$numberDecimal"
        raise "Bad $numberDecimal" unless pull.kind.string?
        builder[key] = Decimal128.new(pull.read_string)
        raise "Bad $numberDecimal" unless pull.kind.end_object?
      when "$binary"
        binary_base64 = nil
        binary_subtype = nil
        raise "Bad $binary" unless pull.kind.begin_object?
        pull.read_object { |binary_key|
          if binary_key == "base64"
            raise "Bad $binary" unless pull.kind.string?
            binary_base64 = pull.read_string
          elsif binary_key == "subType"
            raise "Bad $binary" unless pull.kind.string?
            binary_subtype = pull.read_string
          else
            raise "Bad $binary"
          end
        }
        raise "Bad $binary" if binary_base64.nil? || binary_subtype.nil?
        binary_bytes = Base64.decode(binary_base64)
        subtype = Binary::SubType.from_value(binary_subtype.to_u8(16))
        if subtype.uuid?
          builder[key] = UUID.new(binary_bytes)
        else
          builder[key] = Binary.new(subtype, binary_bytes)
        end
        raise "Bad $binary" unless pull.kind.end_object?
      when "$uuid"
        raise "Bad $uuid" unless pull.kind.string?
        uuid_str = pull.read_string
        raise "Bad $uuid" unless uuid_str.bytesize == 36
        builder[key] = UUID.new(uuid_str)
        raise "Bad $uuid" unless pull.kind.end_object?
      when "$code"
        raise "Bad $code" unless pull.kind.string?
        code_str = pull.read_string
        scope_document = nil
        unless pull.kind.end_object?
          scope_key = pull.read_object_key
          raise "Expected $scope in $code object, got: #{scope_key}" unless scope_key == "$scope"
          raise "Bad $code" unless pull.kind.begin_object?
          scope_document = BSON.new(pull)
        end
        builder[key] = Code.new(code_str, scope_document)
        raise "Bad $code" unless pull.kind.end_object?
      when "$timestamp"
        raise "Bad $timestamp" unless pull.kind.begin_object?
        timestamp_i = nil
        timestamp_t = nil
        pull.read_object { |timestamp_key|
          if timestamp_key == "i"
            raise "Bad $timestamp" unless pull.kind.int?
            timestamp_i = pull.read_int
          elsif timestamp_key == "t"
            raise "Bad $timestamp" unless pull.kind.int?
            timestamp_t = pull.read_int
          else
            raise "Bad $timestamp"
          end
        }
        raise "Bad $timestamp" if timestamp_i.nil? || timestamp_t.nil?
        builder[key] = Timestamp.new(timestamp_t.to_u32, timestamp_i.to_u32)
        raise "Bad $timestamp" unless pull.kind.end_object?
      when "$regularExpression"
        raise "Bad $regularExpression" unless pull.kind.begin_object?
        regex_pattern = nil
        regex_options = nil

        pull.read_object { |regex_key|
          if regex_key == "pattern"
            raise "Bad $regularExpression" unless pull.kind.string?
            regex_pattern = pull.read_string
            raise "Bad $regularExpression" if regex_pattern.includes?('\u0000')
          elsif regex_key == "options"
            raise "Bad $regularExpression" unless pull.kind.string?
            regex_options = pull.read_string
            raise "Bad $regularExpression" if regex_options.includes?('\u0000')
          else
            raise "Bad $regularExpression"
          end
        }
        raise "Bad $regularExpression" if regex_pattern.nil? || regex_options.nil?

        builder[key] = Regex.new(regex_pattern, Decoder.parse_regex_options(regex_options))
        raise "Bad $regularExpression" unless pull.kind.end_object?
      when "$dbPointer"
        db_ref = nil
        db_oid = nil
        raise "Bad $dbPointer" unless pull.kind.begin_object?
        pull.read_object { |db_ptr_key|
          if db_ptr_key == "$ref"
            raise "Bad $dbPointer" unless pull.kind.string?
            db_ref = pull.read_string
          elsif db_ptr_key == "$id"
            raise "Bad $dbPointer" unless pull.kind.begin_object?
            pull.read_object { |oid_key|
              if oid_key == "$oid"
                raise "Bad $dbPointer" unless pull.kind.string?
                db_oid = pull.read_string
              else
                raise "Bad $dbPointer"
              end
            }
          else
            raise "Bad $dbPointer"
          end
        }
        raise "Bad $dbPointer" if db_ref.nil? || db_oid.nil?
        builder[key] = DBPointer.new(db_ref, ObjectId.new db_oid)
        raise "Bad $dbPointer" unless pull.kind.end_object?
      when "$date"
        if pull.kind.string?
          builder[key] = Time.new(pull)
        else
          date_time : String? = nil
          raise "Bad $date" unless pull.kind.begin_object?
          pull.read_object { |date_key|
            if date_key == "$numberLong"
              raise "Bad $date" unless pull.kind.string?
              date_time = pull.read_string
            else
              raise "Bad $date"
            end
          }
          raise "Expected $numberLong in $date object" unless date_time
          builder[key] = Time.unix_ms(date_time.to_i64)
        end
        raise "Bad $date" unless pull.kind.end_object?
      when "$minKey"
        raise "Bad $minKey" unless pull.kind.int?
        val = pull.read_int
        raise "Bad $minKey" unless val == 1
        builder[key] = MinKey.new
        raise "Bad $minKey" unless pull.kind.end_object?
      when "$maxKey"
        raise "Bad $maxKey" unless pull.kind.int?
        val = pull.read_int
        raise "Bad $maxKey" unless val == 1
        builder[key] = MaxKey.new
        raise "Bad $maxKey" unless pull.kind.end_object?
      when "$undefined"
        raise "Bad $undefined" unless pull.kind.bool?
        val = pull.read_bool
        raise "Bad $undefined" unless val == true
        builder[key] = Undefined.new
        raise "Bad $undefined" unless pull.kind.end_object?
      else
        object_builder = Builder.new
        until pull.kind.end_object?
          raise "Bad document key" if inner_key.includes?('\u0000')

          self.decode_json_key(pull.kind, inner_key, object_builder, pull)
          inner_key = pull.read_object_key unless pull.kind.end_object?
        end
        builder[key] = BSON.new(object_builder.to_bson)
      end
    end
  end
end
