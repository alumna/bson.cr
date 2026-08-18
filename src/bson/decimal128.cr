struct BSON
  # 128-bit decimal floating point.
  #
  # See: https://github.com/mongodb/specifications/blob/master/source/bson-decimal128/decimal128.rst
  struct Decimal128
    getter low : UInt64, high : UInt64

    # Infinity mask.
    INFINITY_MASK = 0x7800000000000000_u64
    # NaN mask.
    NAN_MASK = 0x7c00000000000000_u64
    # SNaN mask.
    SNAN_MASK = 1_u64 << 57
    # Signed bit mask.
    SIGN_BIT_MASK = 1_u64 << 63
    # The two highest bits of the 64 high order bits.
    TWO_HIGHEST_BITS_SET = 3_u64 << 61
    # Exponent offset.
    EXPONENT_OFFSET = 6176
    # Minimum exponent.
    MIN_EXPONENT = -6176
    # Maximum exponent.
    MAX_EXPONENT = 6111
    # Maximum digits of precision.
    MAX_DIGITS_OF_PRECISION = 34

    # String representing a NaN value.
    NAN_STRING = "NaN"
    # String representing an Infinity value.
    INFINITY_STRING = "Infinity"

    # Convert parts representing a Decimal128 into the corresponding bits.
    def initialize(significand : UInt128, exponent : Int32, is_negative : Bool)
      @low, @high = Decimal128.parts_to_bits(significand, exponent, is_negative)
    end

    def initialize(string : String)
      s = string
      is_neg = s.starts_with?('-')
      s_no_sign = is_neg || s.starts_with?('+') ? s[1..] : s

      # Handle Specials
      if s_no_sign.compare("nan", case_insensitive: true) == 0
        @low = 0_u64
        @high = NAN_MASK | (is_neg ? SIGN_BIT_MASK : 0_u64)
        return
      elsif s_no_sign.compare("snan", case_insensitive: true) == 0
        @low = 0_u64
        @high = NAN_MASK | SNAN_MASK | (is_neg ? SIGN_BIT_MASK : 0_u64)
        return
      elsif s_no_sign.compare("inf", case_insensitive: true) == 0 || s_no_sign.compare("infinity", case_insensitive: true) == 0
        @low = 0_u64
        @high = INFINITY_MASK | (is_neg ? SIGN_BIT_MASK : 0_u64)
        return
      end

      # Find exponent (E or e)
      e_idx = s_no_sign.each_byte.with_index.find { |b, _| b == 'E'.ord || b == 'e'.ord }.try &.[1]
      if e_idx
        digits_str = s_no_sign[0...e_idx]
        exp_str = s_no_sign[e_idx + 1..]
        sci_exp = exp_str.to_i?(10, whitespace: false) || raise InvalidString.new
      else
        digits_str = s_no_sign
        sci_exp = 0
      end

      raise InvalidString.new if digits_str.empty? || digits_str == "."

      # Find decimal point
      dot_idx = digits_str.index('.')
      if dot_idx
        before = digits_str[0...dot_idx]
        after = digits_str[dot_idx + 1..]
        raise InvalidString.new if after.includes?('.')
        sig_str = before + after
        exponent = -after.bytesize + sci_exp
      else
        sig_str = digits_str
        exponent = sci_exp
      end

      # Strip leading zeros
      sig_str = sig_str.lstrip('0')
      sig_str = "0" if sig_str.empty?

      exponent, sig_str = Decimal128.round_exact(exponent, sig_str)
      exponent, sig_str = Decimal128.clamp(exponent, sig_str)

      # Read digits into UInt128 without a second string-to-number pass.
      sig_val = parse_significand(sig_str)
      @low, @high = Decimal128.parts_to_bits(sig_val, exponent.to_i, is_neg)
    end

    def initialize(bytes : Bytes)
      @low = IO::ByteFormat::LittleEndian.decode(UInt64, bytes[0, 8])
      @high = IO::ByteFormat::LittleEndian.decode(UInt64, bytes[8, 8])
    end

    def nan?
      (@high & NAN_MASK) == NAN_MASK
    end

    def negative?
      (@high & SIGN_BIT_MASK) == SIGN_BIT_MASK
    end

    def infinity?
      (@high & INFINITY_MASK) == INFINITY_MASK
    end

    def to_s(io : IO) : Nil
      return io << NAN_STRING if nan?
      io << '-' if negative?
      if infinity?
        io << INFINITY_STRING
      else
        write_value(io)
      end
    end

    def to_json(builder : JSON::Builder)
      to_canonical_extjson(builder)
    end

    # Serialize to a canonical extended json representation.
    def to_canonical_extjson(builder : JSON::Builder)
      builder.object {
        builder.string("$numberDecimal")
        builder.string { |io| self.to_s(io) }
      }
    end

    # Write BSON byte representation directly to an IO.
    def to_io(io : IO, format : IO::ByteFormat = IO::ByteFormat::LittleEndian) : Nil
      io.write_bytes(@low, format)
      io.write_bytes(@high, format)
    end

    # BSON byte representation.
    def bytes : Bytes
      slice = Bytes.new(16)
      IO::ByteFormat::LittleEndian.encode(@low, slice[0, 8])
      IO::ByteFormat::LittleEndian.encode(@high, slice[8, 8])
      slice
    end

    class InvalidString < Error
    end

    class InvalidRange < Error
    end

    protected def self.parts_to_bits(significand : UInt128, exponent : Int32, is_negative : Bool)
      validate_range!(exponent, significand)
      exponent += EXPONENT_OFFSET
      high = (significand >> 64).to_u64!
      low = (significand & 0xFFFFFFFFFFFFFFFF_u128).to_u64!

      if (high >> 49) == 1
        high &= 0x7fffffffffff_u64
        high |= TWO_HIGHEST_BITS_SET
        high |= (exponent.to_u64 & 0x3fff_u64) << 47
      else
        high |= exponent.to_u64 << 49
      end

      high |= SIGN_BIT_MASK if is_negative

      {low, high}
    end

    protected def self.round_exact(exponent, significand)
      if exponent < MIN_EXPONENT
        if significand.each_byte.all? { |b| b == 0x30_u8 }
          round = MIN_EXPONENT - exponent
          exponent += round
        else
          tz = count_trailing_zeros(significand)
          if tz > 0
            round = {MIN_EXPONENT - exponent, tz}.min
            significand = significand[0, significand.bytesize - round]
            exponent += round
          end
        end
      elsif significand.bytesize > MAX_DIGITS_OF_PRECISION
        tz = count_trailing_zeros(significand)
        if tz > 0
          round = {tz, significand.bytesize - MAX_DIGITS_OF_PRECISION, MAX_EXPONENT - exponent}.min
          significand = significand[0, significand.bytesize - round]
          exponent += round
        end
      end
      {exponent, significand}
    end

    protected def self.clamp(exponent, significand)
      if exponent > MAX_EXPONENT
        if significand.each_byte.all? { |b| b == 0x30_u8 }
          adjust = exponent - MAX_EXPONENT
          significand = "0"
        else
          adjust = {exponent - MAX_EXPONENT, MAX_DIGITS_OF_PRECISION - significand.bytesize}.min
          significand += "0" * adjust
        end
        exponent -= adjust
      end

      {exponent, significand}
    end

    protected def self.validate_range!(exponent : Int32, significand : UInt128)
      unless valid_significand?(significand) && valid_exponent?(exponent)
        raise InvalidRange.new
      end
    end

    protected def self.valid_significand?(significand : UInt128)
      significand < 10000000000000000000000000000000000_u128
    end

    protected def self.valid_exponent?(exponent : Int32)
      exponent <= MAX_EXPONENT && exponent >= MIN_EXPONENT
    end

    private def self.count_trailing_zeros(s : String) : Int32
      count = 0
      (s.bytesize - 1).downto(0) do |i|
        break unless s.to_unsafe[i] == 0x30_u8
        count += 1
      end
      count < s.bytesize ? count : 0
    end

    private def parse_significand(s : String) : UInt128
      raise InvalidString.new if s.empty?
      raise InvalidRange.new if s.bytesize > 39
      value = 0_u128
      s.each_byte do |byte|
        raise InvalidString.new unless 0x30_u8 <= byte <= 0x39_u8
        value = (value * 10) + (byte - 0x30_u8)
      end
      value
    end

    private def write_value(io : IO) : Nil
      two_highest = (@high & TWO_HIGHEST_BITS_SET) == TWO_HIGHEST_BITS_SET
      if two_highest
        exp = ((@high & 0x1fffe00000000000_u64) >> 47).to_i - EXPONENT_OFFSET
        sig = "0"
      else
        exp = ((@high & 0x7fff800000000000_u64) >> 49).to_i - EXPONENT_OFFSET
        sig_val = (@high & 0x1ffffffffffff_u64).to_u128 << 64 | @low
        sig = sig_val.to_s
      end

      sci_exp = (sig.bytesize - 1) + exp

      if exp > 0 || sci_exp < -6
        io << sig.to_unsafe[0].chr
        if sig.bytesize > 1
          io << '.'
          io.write(sig.to_slice[1..])
        end
        io << 'E'
        io << '+' if sci_exp >= 0
        sci_exp.to_s(io)
      elsif exp < 0
        if sig.bytesize > exp.abs
          dec = sig.bytesize - exp.abs
          io.write(sig.to_slice[0...dec])
          io << '.'
          io.write(sig.to_slice[dec..])
        else
          io << "0."
          (exp + sig.bytesize).abs.times { io << '0' }
          io << sig
        end
      else
        io << sig
      end
    end
  end
end
