struct BSON
  private module Decoder
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
          raise Error.new("Bad document key") if inner_key.includes?('\u0000')
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
        raise Error.new("Bad $oid") unless pull.kind.string?
        builder[key] = ObjectId.new(pull.read_string)
        raise Error.new("Bad $oid") unless pull.kind.end_object?
      when "$symbol"
        raise Error.new("Bad $symbol") unless pull.kind.string?
        builder[key] = Symbol.new(pull.read_string)
        raise Error.new("Bad $symbol") unless pull.kind.end_object?
      when "$numberInt"
        raise Error.new("Bad $numberInt") unless pull.kind.string?
        builder[key] = pull.read_string.to_i32
        raise Error.new("Bad $numberInt") unless pull.kind.end_object?
      when "$numberLong"
        raise Error.new("Bad $numberLong") unless pull.kind.string?
        builder[key] = pull.read_string.to_i64
        raise Error.new("Bad $numberLong") unless pull.kind.end_object?
      when "$numberDouble"
        raise Error.new("Bad $numberDouble") unless pull.kind.string?
        double_str = pull.read_string
        builder[key] = case double_str
                       when "Infinity"  then Float64::INFINITY
                       when "-Infinity" then -Float64::INFINITY
                       when "NaN"       then Float64::NAN
                       else                  double_str.to_f64
                       end
        raise Error.new("Bad $numberDouble") unless pull.kind.end_object?
      when "$numberDecimal"
        raise Error.new("Bad $numberDecimal") unless pull.kind.string?
        builder[key] = Decimal128.new(pull.read_string)
        raise Error.new("Bad $numberDecimal") unless pull.kind.end_object?
      when "$binary"
        binary_base64 = nil
        binary_subtype = nil
        raise Error.new("Bad $binary") unless pull.kind.begin_object?
        pull.read_object { |binary_key|
          if binary_key == "base64"
            raise Error.new("Bad $binary") unless pull.kind.string?
            binary_base64 = pull.read_string
          elsif binary_key == "subType"
            raise Error.new("Bad $binary") unless pull.kind.string?
            binary_subtype = pull.read_string
          else
            raise Error.new("Bad $binary")
          end
        }
        raise Error.new("Bad $binary") if binary_base64.nil? || binary_subtype.nil?
        binary_bytes = Base64.decode(binary_base64)
        subtype = Binary::SubType.from_value(binary_subtype.to_u8(16))
        if subtype.uuid?
          builder[key] = UUID.new(binary_bytes)
        else
          builder[key] = Binary.new(subtype, binary_bytes)
        end
        raise Error.new("Bad $binary") unless pull.kind.end_object?
      when "$uuid"
        raise Error.new("Bad $uuid") unless pull.kind.string?
        uuid_str = pull.read_string
        raise Error.new("Bad $uuid") unless uuid_str.bytesize == 36
        builder[key] = UUID.new(uuid_str)
        raise Error.new("Bad $uuid") unless pull.kind.end_object?
      when "$code"
        raise Error.new("Bad $code") unless pull.kind.string?
        code_str = pull.read_string
        scope_document = nil
        unless pull.kind.end_object?
          scope_key = pull.read_object_key
          raise Error.new("Expected $scope in $code object, got: #{scope_key}") unless scope_key == "$scope"
          raise Error.new("Bad $code") unless pull.kind.begin_object?
          scope_document = BSON.new(pull)
        end
        builder[key] = Code.new(code_str, scope_document)
        raise Error.new("Bad $code") unless pull.kind.end_object?
      when "$timestamp"
        raise Error.new("Bad $timestamp") unless pull.kind.begin_object?
        timestamp_i = nil
        timestamp_t = nil
        pull.read_object { |timestamp_key|
          if timestamp_key == "i"
            raise Error.new("Bad $timestamp") unless pull.kind.int?
            timestamp_i = pull.read_int
          elsif timestamp_key == "t"
            raise Error.new("Bad $timestamp") unless pull.kind.int?
            timestamp_t = pull.read_int
          else
            raise Error.new("Bad $timestamp")
          end
        }
        raise Error.new("Bad $timestamp") if timestamp_i.nil? || timestamp_t.nil?
        builder[key] = Timestamp.new(timestamp_t.to_u32, timestamp_i.to_u32)
        raise Error.new("Bad $timestamp") unless pull.kind.end_object?
      when "$regularExpression"
        raise Error.new("Bad $regularExpression") unless pull.kind.begin_object?
        regex_pattern = nil
        regex_options = nil

        pull.read_object { |regex_key|
          if regex_key == "pattern"
            raise Error.new("Bad $regularExpression") unless pull.kind.string?
            regex_pattern = pull.read_string
            raise Error.new("Bad $regularExpression") if regex_pattern.includes?('\u0000')
          elsif regex_key == "options"
            raise Error.new("Bad $regularExpression") unless pull.kind.string?
            regex_options = pull.read_string
            raise Error.new("Bad $regularExpression") if regex_options.includes?('\u0000')
          else
            raise Error.new("Bad $regularExpression")
          end
        }
        raise Error.new("Bad $regularExpression") if regex_pattern.nil? || regex_options.nil?

        builder[key] = BSON::Regex.new(regex_pattern, regex_options)
        raise Error.new("Bad $regularExpression") unless pull.kind.end_object?
      when "$dbPointer"
        db_ref = nil
        db_oid = nil
        raise Error.new("Bad $dbPointer") unless pull.kind.begin_object?
        pull.read_object { |db_ptr_key|
          if db_ptr_key == "$ref"
            raise Error.new("Bad $dbPointer") unless pull.kind.string?
            db_ref = pull.read_string
          elsif db_ptr_key == "$id"
            raise Error.new("Bad $dbPointer") unless pull.kind.begin_object?
            pull.read_object { |oid_key|
              if oid_key == "$oid"
                raise Error.new("Bad $dbPointer") unless pull.kind.string?
                db_oid = pull.read_string
              else
                raise Error.new("Bad $dbPointer")
              end
            }
          else
            raise Error.new("Bad $dbPointer")
          end
        }
        raise Error.new("Bad $dbPointer") if db_ref.nil? || db_oid.nil?
        builder[key] = DBPointer.new(db_ref, ObjectId.new db_oid)
        raise Error.new("Bad $dbPointer") unless pull.kind.end_object?
      when "$date"
        if pull.kind.string?
          builder[key] = DateTime.new(Time.new(pull))
        else
          date_time : String? = nil
          raise Error.new("Bad $date") unless pull.kind.begin_object?
          pull.read_object { |date_key|
            if date_key == "$numberLong"
              raise Error.new("Bad $date") unless pull.kind.string?
              date_time = pull.read_string
            else
              raise Error.new("Bad $date")
            end
          }
          raise Error.new("Expected $numberLong in $date object") unless date_time
          builder[key] = DateTime.new(date_time.to_i64)
        end
        raise Error.new("Bad $date") unless pull.kind.end_object?
      when "$minKey"
        raise Error.new("Bad $minKey") unless pull.kind.int?
        val = pull.read_int
        raise Error.new("Bad $minKey") unless val == 1
        builder[key] = MinKey.new
        raise Error.new("Bad $minKey") unless pull.kind.end_object?
      when "$maxKey"
        raise Error.new("Bad $maxKey") unless pull.kind.int?
        val = pull.read_int
        raise Error.new("Bad $maxKey") unless val == 1
        builder[key] = MaxKey.new
        raise Error.new("Bad $maxKey") unless pull.kind.end_object?
      when "$undefined"
        raise Error.new("Bad $undefined") unless pull.kind.bool?
        val = pull.read_bool
        raise Error.new("Bad $undefined") unless val == true
        builder[key] = Undefined.new
        raise Error.new("Bad $undefined") unless pull.kind.end_object?
      else
        object_builder = Builder.new
        until pull.kind.end_object?
          raise Error.new("Bad document key") if inner_key.includes?('\u0000')

          self.decode_json_key(pull.kind, inner_key, object_builder, pull)
          inner_key = pull.read_object_key unless pull.kind.end_object?
        end
        builder[key] = BSON.view(object_builder.to_bson)
      end
    end
  end
end
