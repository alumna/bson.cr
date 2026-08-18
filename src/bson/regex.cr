struct BSON
  # BSON regular expression: a pattern C string and an options C string.
  #
  # This type does not compile the pattern. Unusual or invalid patterns stay
  # as text and can round-trip. Call `#to_regex` when you want a Crystal `Regex`.
  struct Regex
    getter pattern : String
    getter options : String

    # Create from a pattern and option letters. Letters are stored unique and
    # in alphabetical order, as required by the BSON spec.
    def initialize(@pattern : String, options : String = "")
      raise ArgumentError.new("BSON regex pattern cannot contain a null byte") if @pattern.includes?('\0')
      @options = sort_options(options)
    end

    # Create from a Crystal regex. Option letters are the BSON letters only.
    def initialize(regex : ::Regex)
      initialize(regex.source, letters_from(regex.options))
    end

    # Compile as a Crystal `Regex`. Raises if the pattern is not valid PCRE.
    def to_regex : ::Regex
      ::Regex.new(@pattern, crystal_options(@options))
    end

    # Compile as a Crystal `Regex`, or `nil` if the pattern is not valid PCRE.
    def to_regex? : ::Regex?
      to_regex
    rescue ArgumentError | ::Regex::Error
      nil
    end

    def to_json(builder : JSON::Builder)
      to_canonical_extjson(builder)
    end

    # Serialize to a canonical extended json representation.
    #
    # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
    def to_canonical_extjson(builder : JSON::Builder)
      builder.object {
        builder.string("$regularExpression")
        builder.object {
          builder.string("pattern")
          builder.string(@pattern)
          builder.string("options")
          builder.string(@options)
        }
      }
    end

    def ==(other : ::Regex) : Bool
      @pattern == other.source && @options == letters_from(other.options)
    end

    def ==(other : self) : Bool
      @pattern == other.pattern && @options == other.options
    end

    # Map Crystal regex flags to BSON letters in alphabetical order: i, m, s, u, x.
    def self.letters_from(options : ::Regex::Options) : String
      String.build(5) do |io|
        write_letters(io, options)
      end
    end

    # Write BSON regex option letters in alphabetical order: i, m, s, u, x.
    def self.write_letters(io : IO, options : ::Regex::Options) : Nil
      io.write_byte 0x69_u8 if options.ignore_case?
      io.write_byte 0x6d_u8 if options.multiline? || options.multiline_only?
      io.write_byte 0x73_u8 if options.multiline? || options.dotall?
      io.write_byte 0x75_u8 if options.utf_8?
      io.write_byte 0x78_u8 if options.extended?
    end

    # Map BSON option letters to Crystal flags. Unknown letters are ignored.
    def self.crystal_options(ptr : Pointer(UInt8), size : Int) : ::Regex::Options
      modifiers = ::Regex::Options::None
      size.times do |i|
        case (ptr + i).value
        when 0x69_u8 # 'i'
          modifiers |= ::Regex::Options::IGNORE_CASE
        when 0x6d_u8 # 'm'
          modifiers |= ::Regex::Options::MULTILINE_ONLY
        when 0x73_u8 # 's'
          modifiers |= ::Regex::Options::DOTALL
        when 0x75_u8 # 'u'
          modifiers |= ::Regex::Options::UTF_8
        when 0x78_u8 # 'x'
          modifiers |= ::Regex::Options::EXTENDED
        end
      end
      modifiers
    end

    def self.crystal_options(options : String) : ::Regex::Options
      crystal_options(options.to_unsafe, options.bytesize)
    end

    # Unique option letters in alphabetical order. Extra letters are kept.
    def self.sort_options(options : String) : String
      raise ArgumentError.new("BSON regex options cannot contain a null byte") if options.includes?('\0')
      return options if options.bytesize <= 1

      bytes = options.bytes
      bytes.sort!
      String.build(bytes.size) do |io|
        previous = -1
        bytes.each do |byte|
          next if byte.to_i == previous
          io.write_byte byte
          previous = byte.to_i
        end
      end
    end

    private def sort_options(options : String) : String
      self.class.sort_options(options)
    end

    private def letters_from(options : ::Regex::Options) : String
      self.class.letters_from(options)
    end

    private def crystal_options(options : String) : ::Regex::Options
      self.class.crystal_options(options)
    end
  end
end
