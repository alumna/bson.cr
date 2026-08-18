require "big"

struct BSON
  struct Decimal128
    def initialize(big_decimal : BigDecimal)
      initialize(big_decimal.to_s)
    end

    def to_big_d : BigDecimal
      BigDecimal.new(self.to_s)
    end
  end

  class Builder
    def []=(key : String, value : BigDecimal)
      field(:decimal128, key)
      Decimal128.new(value).to_io(@io)
    end
  end
end
