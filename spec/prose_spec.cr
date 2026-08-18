require "./spec_helper"

describe "BSON prose tests" do
  describe "null bytes in cstrings" do
    it "rejects a null byte in a root field name" do
      expect_raises(ArgumentError) do
        BSON.new["a\u0000b"] = 1
      end
    end

    it "rejects a null byte in a sub-document field name" do
      expect_raises(ArgumentError) do
        BSON.new({nested: {"a\u0000b" => 1}})
      end
    end

    it "rejects a null byte in a regex pattern" do
      expect_raises(ArgumentError) do
        BSON.new["a"] = BSON::Regex.new("b\u0000", "i")
      end
    end
  end

  describe "BSON::DateTime" do
    it "stores Y10K and writes canonical ExtJSON" do
      ms = 253_402_300_800_000_i64
      dt = BSON::DateTime.new(ms)
      dt.to_time?.should be_nil
      dt.relaxed?.should be_false

      bson = BSON.new
      bson["a"] = dt
      bson["a"].should eq dt
      bson.to_canonical_extjson.should eq %({"a":{"$date":{"$numberLong":"253402300800000"}}})
    end

    it "converts values that Crystal Time can store" do
      time = Time.utc(2012, 12, 24, 12, 15, 30, nanosecond: 501_000_000)
      dt = BSON::DateTime.new(time)
      dt.to_time.should eq time
      dt.should eq time
    end
  end

  describe "BSON::Regex" do
    it "keeps an unusual pattern without compiling it" do
      rx = BSON::Regex.new("[", "imx")
      rx.pattern.should eq "["
      rx.options.should eq "imx"
      rx.to_regex?.should be_nil
    end

    it "sorts option letters" do
      BSON::Regex.new("abc", "mix").options.should eq "imx"
    end

    it "compiles a valid pattern" do
      rx = BSON::Regex.new("foo*", "ix")
      crystal = rx.to_regex
      crystal.source.should eq "foo*"
      crystal.options.ignore_case?.should be_true
    end
  end

  describe "parse? and from_json?" do
    it "returns a document for valid bytes" do
      bson = BSON.parse(REFERENCE_BYTES)
      bson.data.should eq REFERENCE_BYTES
      BSON.parse?(REFERENCE_BYTES).should eq bson
    end

    it "returns nil for invalid bytes" do
      BSON.parse?(Bytes[1, 0, 0, 0, 0]).should be_nil
    end

    it "returns nil for invalid ExtJSON" do
      BSON.from_json?(%({"a":{"$oid":42}})).should be_nil
    end
  end

  describe "BSON.build" do
    it "writes fields in one pass" do
      bson = BSON.build do |builder|
        builder["a"] = 1_i32
        builder["b"] = "x"
      end
      bson["a"].should eq 1
      bson["b"].should eq "x"
    end
  end

  describe "ObjectId process unique bytes" do
    it "changes the random prefix after reset_process_unique!" do
      first = BSON::ObjectId.new
      BSON::ObjectId.reset_process_unique!
      second = BSON::ObjectId.new
      first.to_slice[4, 5].should_not eq second.to_slice[4, 5]
    end
  end

  describe "ObjectId timestamp" do
    it "reads the timestamp as an unsigned 32-bit value" do
      {
        "00000000aabbccddee000001" => Time.utc(1970, 1, 1, 0, 0, 0),
        "7fffffffaabbccddee000001" => Time.utc(2038, 1, 19, 3, 14, 7),
        "80000000aabbccddee000001" => Time.utc(2038, 1, 19, 3, 14, 8),
        "ffffffffaabbccddee000001" => Time.utc(2106, 2, 7, 6, 28, 15),
      }.each do |hex, expected|
        oid = BSON::ObjectId.new(hex)
        oid.timestamp.should eq expected.to_unix.to_u32
        oid.generation_time.should eq expected
      end
    end

    it "rejects hex strings that are not 24 hex characters" do
      expect_raises(ArgumentError) { BSON::ObjectId.new("zz") }
      expect_raises(ArgumentError) { BSON::ObjectId.new("57e193d7a9cc81b4027498b") }
      expect_raises(ArgumentError) { BSON::ObjectId.new("57e193d7a9cc81b4027498b5ff") }
      expect_raises(ArgumentError) { BSON::ObjectId.new("not-a-valid-objectid-hex") }
    end

    it "copies 12-byte input into the ObjectId" do
      bytes = Bytes.new(12) { |i| i.to_u8 }
      oid = BSON::ObjectId.new(bytes)
      oid.data.should eq bytes
      bytes[0] = 0xFF_u8
      oid.data[0].should eq 0
    end
  end

  describe "UUID representation" do
    uuid = UUID.new("00112233-4455-6677-8899-aabbccddeeff")

    it "encodes the standard representation as subtype 4" do
      binary = BSON::Binary.new(uuid)
      binary.subtype.should eq BSON::Binary::SubType::UUID
      binary.data.hexstring.should eq "00112233445566778899aabbccddeeff"
      binary.as_uuid.should eq uuid
      binary.as_uuid(:standard).should eq uuid
    end

    it "encodes the Java legacy representation as subtype 3" do
      binary = BSON::Binary.new(uuid, :java_legacy)
      binary.subtype.should eq BSON::Binary::SubType::UUID_Old
      binary.data.hexstring.should eq "7766554433221100ffeeddccbbaa9988"
      binary.as_uuid(:java_legacy).should eq uuid
    end

    it "encodes the C# legacy representation as subtype 3" do
      binary = BSON::Binary.new(uuid, :c_sharp_legacy)
      binary.subtype.should eq BSON::Binary::SubType::UUID_Old
      binary.data.hexstring.should eq "33221100554477668899aabbccddeeff"
      binary.as_uuid(:c_sharp_legacy).should eq uuid
    end

    it "encodes the Python legacy representation as subtype 3" do
      binary = BSON::Binary.new(uuid, :python_legacy)
      binary.subtype.should eq BSON::Binary::SubType::UUID_Old
      binary.data.hexstring.should eq "00112233445566778899aabbccddeeff"
      binary.as_uuid(:python_legacy).should eq uuid
    end

    it "rejects a mismatched UUID representation" do
      standard = BSON::Binary.new(uuid)
      expect_raises(Exception) { standard.as_uuid(:java_legacy) }
      expect_raises(Exception) { standard.as_uuid(:c_sharp_legacy) }
      expect_raises(Exception) { standard.as_uuid(:python_legacy) }

      legacy = BSON::Binary.new(uuid, :python_legacy)
      expect_raises(Exception) { legacy.as_uuid }
      expect_raises(Exception) { legacy.as_uuid(:standard) }
    end
  end

  describe "packed bit ignored bits" do
    it "rejects encoding when ignored bits are not zero" do
      expect_raises(Exception) do
        BSON::Binary.from_packed_bit_vector([0b11111111_u8], padding: 7)
      end
    end

    it "rejects decoding when ignored bits are not zero" do
      expect_raises(Exception) do
        BSON::Binary.new(:vector, Bytes[0x10, 0x07, 0xFF]).to_vector
      end
    end

    it "accepts ignored bits that are zero" do
      binary = BSON::Binary.from_packed_bit_vector([0b10000000_u8], padding: 7)
      vector = binary.to_vector
      vector.padding.should eq 7
      vector.as_packed_bit.should eq Bytes[0b10000000]
    end
  end
end
