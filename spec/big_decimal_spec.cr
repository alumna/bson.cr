require "./spec_helper"
require "../src/bson/optional/big_decimal"

describe "BSON::Decimal128 BigDecimal" do
  it "builds from BigDecimal and converts back" do
    big = BigDecimal.new("1234.5")
    decimal = BSON::Decimal128.new(big)
    decimal.to_big_d.should eq big

    bson = BSON.new
    bson["d"] = big
    bson["d"].as(BSON::Decimal128).to_s.should eq "1234.5"
  end
end
