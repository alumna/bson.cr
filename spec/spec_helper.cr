require "spec"
require "json"
require "../src/bson"
require "./reference_data"

module Runner::Corpus
  extend self

  def run(name : String, *focus)
    corpus = File.open("./spec/corpus/bson-corpus/tests/#{name}.json") do |file|
      JSON.parse(file)
    end

    # Valid tests
    corpus["valid"]?.try &.as_a.each { |test|
      description = test["description"].as_s
      next if test["ignore"]?
      it description, focus: focus.includes?(description) do
        # Parse canonical bson
        bson_bytes = test["canonical_bson"].as_s.hexbytes
        bson = BSON.new(bson_bytes)
        # Validate
        bson.validate!
        # Ensure that the underlying bytes are equal
        bson.data.should eq bson_bytes
        # Native decode then encode must produce canonical BSON.
        unless test["lossy"]? == true
          bson.canonicalize.data.should eq bson_bytes
        end
        if degenerate_bson = test["degenerate_bson"]?
          BSON.new(degenerate_bson.as_s.hexbytes).canonicalize.data.should eq bson_bytes
        end
        # Serialize to canonical extended json and compare with the expected canonical json.
        bson.to_canonical_extjson.should eq JSON.parse(test["canonical_extjson"].as_s).to_json
        # Serialize to json and compare with the expected relaxed extended json.
        json = bson.to_json
        if relaxed_json = test["relaxed_extjson"]?
          JSON.parse(json).should eq JSON.parse(relaxed_json.as_s)
        end
        # JSON roundtrip
        unless test["ignore_json_roundtrip"]?
          BSON.from_json(json).to_json.should eq json

          # Strict BSON byte roundtrip (only if not lossy)
          unless test["lossy"]? == true
            BSON.from_json(test["canonical_extjson"].as_s).data.should eq bson_bytes
          end
        end
        if degenerate_extjson = test["degenerate_extjson"]?
          unless test["lossy"]? == true
            BSON.from_json(degenerate_extjson.as_s).data.should eq bson_bytes
          end
        end
      end
    }

    # Errors
    corpus["decodeErrors"]?.try &.as_a.each { |test|
      description = test["description"].as_s
      it description, focus: focus.includes?(description), tags: "decode-errors" do
        expect_raises(Exception) {
          bson = BSON.new(test["bson"].as_s.hexbytes)
          bson.validate!
          puts bson.to_json
        }
      end
    }

    # Parse Errors
    corpus["parseErrors"]?.try &.as_a.each { |test|
      description = test["description"].as_s

      # DBRef is a driver-level convention, not a BSON type. The pure BSON
      # library correctly treats it as a standard document, so we skip these.
      next if description.starts_with?("Bad DBRef")

      it "parse error: #{description}", focus: focus.includes?(description), tags: "parse-errors" do
        expect_raises(Exception) do
          BSON.from_json(test["string"].as_s)
        end
      end
    }
  end
end
