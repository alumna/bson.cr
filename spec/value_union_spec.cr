require "./spec_helper"

class TimeOnlyDoc
  include BSON::Serializable

  property t : Time
end

class DateTimeOnlyDoc
  include BSON::Serializable

  property t : BSON::DateTime
end

class ValueDoc
  include BSON::Serializable

  property v : BSON::Value
end

class ValueArrayDoc
  include BSON::Serializable

  property items : Array(BSON::Value)
end

class ValueHashDoc
  include BSON::Serializable

  property map : Hash(String, BSON::Value)
end

class TimeArrayDoc
  include BSON::Serializable

  property items : Array(Time)
end

class DateTimeArrayDoc
  include BSON::Serializable

  property items : Array(BSON::DateTime)
end

class TimeHashDoc
  include BSON::Serializable

  property map : Hash(String, Time)
end

class RegexOnlyDoc
  include BSON::Serializable

  property r : Regex
end

class BsonRegexOnlyDoc
  include BSON::Serializable

  property r : BSON::Regex
end

describe "BSON::Value unions after DateTime / Regex decode" do
  it "still converts DateTime to Time when the field is Time" do
    ms = Time.utc(2020, 1, 2, 3, 4, 5).to_unix_ms
    bson = BSON.build { |b| b["t"] = BSON::DateTime.new(ms) }
    TimeOnlyDoc.from_bson(bson).t.should eq Time.unix_ms(ms)
  end

  it "keeps DateTime when the field is BSON::DateTime" do
    ms = 253_402_300_800_000_i64 # Y10K, outside Crystal Time
    bson = BSON.build { |b| b["t"] = BSON::DateTime.new(ms) }
    DateTimeOnlyDoc.from_bson(bson).t.milliseconds.should eq ms
  end

  it "compiles and keeps DateTime when the field is BSON::Value" do
    ms = Time.utc(2021, 6, 1, 12, 0, 0).to_unix_ms
    bson = BSON.build { |b| b["v"] = BSON::DateTime.new(ms) }
    value = ValueDoc.from_bson(bson).v
    value.should be_a(BSON::DateTime)
    value.as(BSON::DateTime).milliseconds.should eq ms
  end

  it "compiles Array(BSON::Value) with a datetime element" do
    ms = Time.utc(2022, 3, 4, 5, 6, 7).to_unix_ms
    bson = BSON.build do |b|
      b["items"] = [BSON::DateTime.new(ms), "x", 1]
    end
    items = ValueArrayDoc.from_bson(bson).items
    items[0].should be_a(BSON::DateTime)
    items[1].should eq "x"
    items[2].should eq 1
  end

  it "converts DateTime elements when the array is Array(Time)" do
    ms = Time.utc(2020, 1, 2, 3, 4, 5).to_unix_ms
    bson = BSON.build { |b| b["items"] = [BSON::DateTime.new(ms)] }
    items = TimeArrayDoc.from_bson(bson).items
    items[0].should be_a(Time)
    items[0].should eq Time.unix_ms(ms)
  end

  it "keeps DateTime elements when the array is Array(BSON::DateTime)" do
    ms = 253_402_300_800_000_i64
    bson = BSON.build { |b| b["items"] = [BSON::DateTime.new(ms)] }
    items = DateTimeArrayDoc.from_bson(bson).items
    items[0].milliseconds.should eq ms
  end

  it "compiles Hash(String, BSON::Value) with a datetime value" do
    ms = Time.utc(2023, 8, 9, 10, 11, 12).to_unix_ms
    inner = BSON.build { |b| b["d"] = BSON::DateTime.new(ms) }
    bson = BSON.build { |b| b["map"] = inner }
    map = ValueHashDoc.from_bson(bson).map
    map["d"].should be_a(BSON::DateTime)
  end

  it "converts DateTime values when the hash is Hash(String, Time)" do
    ms = Time.utc(2023, 8, 9, 10, 11, 12).to_unix_ms
    inner = BSON.build { |b| b["d"] = BSON::DateTime.new(ms) }
    bson = BSON.build { |b| b["map"] = inner }
    map = TimeHashDoc.from_bson(bson).map
    map["d"].should be_a(Time)
    map["d"].should eq Time.unix_ms(ms)
  end

  it "still converts BSON::Regex to Regex when the field is Regex" do
    bson = BSON.build { |b| b["r"] = BSON::Regex.new("foo*", "i") }
    rx = RegexOnlyDoc.from_bson(bson).r
    rx.should be_a(Regex)
    rx.source.should eq "foo*"
  end

  it "keeps BSON::Regex when the field is BSON::Regex" do
    bson = BSON.build { |b| b["r"] = BSON::Regex.new("[", "ix") }
    rx = BsonRegexOnlyDoc.from_bson(bson).r
    rx.pattern.should eq "["
    rx.options.should eq "ix"
  end

  it "compiles and keeps BSON::Regex when the field is BSON::Value" do
    bson = BSON.build { |b| b["v"] = BSON::Regex.new("foo*", "i") }
    value = ValueDoc.from_bson(bson).v
    value.should be_a(BSON::Regex)
    regex = value.as(BSON::Regex)
    regex.pattern.should eq "foo*"
    regex.options.should eq "i"
  end
end
