# spec/vector_spec.cr
require "./spec_helper"

describe "BSON Binary Vector (Subtype 9)" do
  {% for file in %w(float32 int8 packed_bit) %}
    describe {{file}} do
      corpus = JSON.parse(File.read("./spec/corpus/vector/{{file.id}}.json"))
      test_key = corpus["test_key"].as_s

      corpus["tests"].as_a.each do |test|
        it test["description"].as_s do
          valid = test["valid"].as_bool

          if valid
            canonical_bson = test["canonical_bson"].as_s.hexbytes
            bson = BSON.new(canonical_bson)
            bson.validate!

            # Check decoding
            binary : BSON::Binary? = nil
            bson.each do |k, v, code, subtype|
              if k == test_key
                binary = BSON::Binary.new(subtype.not_nil!, v.as(Bytes))
                break # Short-circuit BSON loop once found
              end
            end
            binary = binary.not_nil!

            binary.subtype.vector?.should be_true

            vec = binary.to_vector
            vec.dtype.value.should eq test["dtype_hex"].as_s.lchop("0x").to_i(16)
            vec.padding.should eq test["padding"].as_i

            # Check encoding
            vector_arr = test["vector"].as_a

            case vec.dtype
            when .float32?
              arr = vector_arr.map do |v|
                if v.as_h? && v["$numberDouble"]?
                  str = v["$numberDouble"].as_s
                  if str == "Infinity"
                    Float32::INFINITY
                  elsif str == "-Infinity"
                    -Float32::INFINITY
                  elsif str == "NaN"
                    Float32::NAN
                  else
                    str.to_f32
                  end
                else
                  v.as_f.to_f32
                end
              end

              encoded = BSON::Binary.from_vector(arr)

              # Enforce Exact Float Equality after Decoding (Mandated by Spec)
              decoded_arr = vec.as_float32
              decoded_arr.size.should eq arr.size
              decoded_arr.each_with_index do |d, i|
                if arr[i].nan?
                  d.nan?.should be_true
                else
                  d.should eq arr[i]
                end
              end

            when .int8?
              arr = vector_arr.map(&.as_i)
              encoded = BSON::Binary.from_vector(arr.map(&.to_i8))
              # `.to_a` is needed since `vec.as_int8` now returns a raw Slice(Int8)
              # to prevent memory allocations.
              vec.as_int8.to_a.should eq arr.map(&.to_i8)

            when .packed_bit?
              arr = vector_arr.map(&.as_i.to_u8)
              encoded = BSON::Binary.from_packed_bit_vector(arr, test["padding"].as_i)
              # `.to_a` is needed since `vec.as_packed_bit` now returns a raw Bytes (Slice(UInt8))
              vec.as_packed_bit.to_a.should eq arr
            else
              raise "Unknown dtype"
            end

            # Note: We rely on byte-level representation for the final roundtrip check
            # here (`encoded.data.should eq binary.data`) to explicitly ensure that
            # nuances around IEEE 754 NaN bit patterns and padded bits perfectly
            # match the canonical hexstring representation mandated by the spec.
            encoded.data.should eq binary.data
          else
            # Invalid cases should raise an exception during either decode or encode
            if canonical_bson = test["canonical_bson"]?
              expect_raises(Exception) do
                bson = BSON.new(canonical_bson.as_s.hexbytes)
                bin : BSON::Binary? = nil
                bson.each do |k, v, code, subtype|
                  if k == test_key
                    bin = BSON::Binary.new(subtype.not_nil!, v.as(Bytes))
                    break
                  end
                end
                bin.not_nil!.to_vector
              end
            elsif vector_any = test["vector"]?
              expect_raises(Exception) do
                vector_arr = vector_any.as_a
                dtype = test["dtype_hex"].as_s.lchop("0x").to_i(16)
                padding = test["padding"]?.try(&.as_i) || 0

                if dtype == 0x27
                  arr = vector_arr.map { |v| v.as_f.to_f32 }
                  BSON::Binary::Vector.new(BSON::Binary::Vector::DataType::Float32, Bytes.new(arr.size * 4), padding.to_u8!)
                elsif dtype == 0x03
                  arr = vector_arr.map { |v| v.as_i }
                  BSON::Binary.from_vector(arr)
                elsif dtype == 0x10
                  arr = vector_arr.map { |v| v.as_i }
                  BSON::Binary.from_packed_bit_vector(arr, padding)
                end
              end
            end
          end
        end
      end
    end
  {% end %}
end
