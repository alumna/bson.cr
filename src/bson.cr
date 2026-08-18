{% raise "alumna/bson.cr requires a little-endian architecture" if flag?(:big_endian) %}

require "json"
require "base64"
require "./bson/error"
require "./bson/helpers/*"
require "./bson/*"
require "./bson/ext/*"

# **BSON is a binary format in which zero or more ordered key/value pairs are stored as a single entity.**
#
# BSON [bee · sahn], short for Binary JSON, is a binary-encoded serialization of JSON-like documents.
# Like JSON, BSON supports the embedding of documents and arrays within other documents and arrays.
# BSON also contains extensions that allow representation of data types that are not part of the JSON spec.
# For example, BSON has a Date type and a BinData type.
#
# [See: http://bsonspec.org/](http://bsonspec.org/)
#
# ```
# require "bson"
#
# data = BSON.new({
#   hello: "world",
#   time:  Time.utc,
#   name:  BSON.new({
#     first_name: "John",
#     last_name:  "Doe",
#   }),
#   fruits: ["Orange", "Banana"],
# })
#
# puts data.to_json
# # => {"hello":"world","time":{"$date":"2020-05-18T07:32:13.621000000Z"},"name":{"first_name":"John","last_name":"Doe"},"fruits":["Orange","Banana"]}
# ```
struct BSON
  # Underlying bytes
  getter data

  include Enumerable(Item)
  include Iterable(Item)
  include Comparable(BSON)

  # Allocate a BSON instance from a byte array.
  #
  # NOTE: The byte array is cloned.
  #
  # ```
  # data = "160000000378000E0000000261000200000062000000".hexbytes
  # io = IO::Memory.new(data)
  # bson = BSON.new(io)
  # puts bson.to_json # => {"x":{"a":"b"}}
  # ```
  def initialize(data : Bytes? = nil, validate : Bool = false)
    if d = data
      check_header!(d)
      @data = d.clone
    else
      @data = empty_document_bytes
    end

    # [Correctness] Act upon the `validate` argument
    validate! if validate
  end

  # Create a BSON document over *data* without copying the bytes.
  #
  # The slice must stay valid for the life of the document. Nested values
  # decoded from a parent document use this path.
  def self.view(data : Bytes, validate : Bool = false) : self
    document = new(no_copy: data)
    document.check_header!(data)
    document.validate! if validate
    document
  end

  private def initialize(*, no_copy data : Bytes)
    @data = data
  end

  protected def check_header!(data : Bytes) : Int32
    raise Error.new("Invalid BSON (wrong field size: #{data.size})") if data.size < 5
    size = IO::ByteFormat::LittleEndian.decode(Int32, data[0, 4])
    Decoder.check_size! data.size, 5, size
    size
  end

  # Read *data* and walk every field. Raises `BSON::Error` when the document is invalid.
  def self.parse(data : Bytes) : self
    new(data, validate: true)
  end

  # Read *data* and walk every field. Returns `nil` when the document is invalid.
  def self.parse?(data : Bytes) : self?
    parse(data)
  rescue Error
    nil
  end

  # Read a document from *io*. Returns `nil` when the bytes are invalid or short.
  def self.from_io?(io : IO) : self?
    new(io)
  rescue Error | IO::Error
    nil
  end

  # Build a document in one pass. Prefer this in Cryomongo instead of many `[]=` calls.
  def self.build(&) : self
    builder = Builder.new
    yield builder
    view(builder.to_bson)
  end

  private def empty_document_bytes : Bytes
    bytes = Bytes.new(5)
    IO::ByteFormat::LittleEndian.encode(5, bytes)
    bytes
  end

  # Allocate a BSON instance from an IO
  #
  # ```
  # data = "160000000378000E0000000261000200000062000000".hexbytes
  # bson = BSON.new(data)
  # puts bson.to_json # => {"x":{"a":"b"}}
  # ```
  def initialize(io : IO)
    size = Int32.from_io(io, IO::ByteFormat::LittleEndian)
    Decoder.check_size! size, 5
    @data = Bytes.new(size)
    IO::ByteFormat::LittleEndian.encode(size, @data[0, 4])
    io.read_fully(@data[4..])
  end

  # Allocate a BSON instance from a NamedTuple.
  #
  # ```
  # puts BSON.new({
  #   hello: "world",
  # }).to_json # => {"hello":"world"}
  # ```
  def initialize(tuple : NamedTuple)
    builder = Builder.new
    tuple.each { |key, value|
      # [Performance] Avoid string interpolation overhead
      builder[key.to_s] = value
    }
    @data = builder.to_bson
  end

  # Allocate a BSON instance from a Hash.
  #
  # ```
  # puts BSON.new({
  #   "hello" => "world",
  # }).to_json # => {"hello":"world"}
  # ```
  def initialize(h : Hash)
    builder = Builder.new
    h.each { |key, value|
      # [Performance] Avoid string interpolation overhead
      builder[key.to_s] = value
    }
    @data = builder.to_bson
  end

  # No-op
  def self.new(bson : BSON)
    bson
  end

  # Allocate a BSON instance from an Array.
  #
  # ```
  # puts BSON.new([1, 2, 3]).to_json # => [1,2,3]
  # ```
  def initialize(ary : Array)
    builder = Builder.new
    ary.each_with_index { |value, index|
      # [Performance] Avoid string interpolation overhead
      builder[index.to_s] = value
    }
    @data = builder.to_bson
  end

  # Allocate a BSON instance from an instance of BSON::Serializable.
  def initialize(serializable : BSON::Serializable)
    @data = serializable.to_bson.data
  end

  protected def initialize(pull : JSON::PullParser)
    builder = Builder.new
    is_array = pull.kind.begin_array?

    if is_array
      index = 0
      pull.read_array do
        Decoder.decode_json_key(pull.kind, index.to_s, builder, pull)
        index += 1
      end
    else
      pull.read_object do |key|
        raise Error.new("Bad document key") if key.includes?('\u0000')
        kind = pull.kind
        Decoder.decode_json_key(kind, key, builder, pull)
      end
    end

    @data = builder.to_bson
  end

  # Return the size of the BSON instance in bytes.
  def size
    data.size
  end

  # Append a key/value pair.
  #
  # ```
  # bson = BSON.new
  # bson["key"] = "value"
  # puts bson.to_json # => {"key":"value"}
  # ```
  def []=(key : String | ::Symbol, value)
    append_with_builder do |builder|
      if value.responds_to? :to_bson
        builder[key.to_s] = value.to_bson
      else
        builder[key.to_s] = value
      end
    end
  end

  # Append a key/value pair and declare it as a BSON array.
  def append_array(key : String | ::Symbol, value : BSON)
    append_with_builder do |builder|
      builder.append_array(key.to_s, value)
    end
  end

  # Append one or more key/value pairs.
  #
  # NOTE: more efficient for appending multiple values than calling `[]=` individually.
  #
  # ```
  # bson = BSON.new
  # bson.append(key: "value", key2: "value2")
  # puts bson.to_json # => {"key":"value","key2":"value2"}
  # ```
  def append(**args)
    append_with_builder do |builder|
      args.each { |key, value|
        # [Performance] Avoid string interpolation overhead
        builder[key.to_s] = value
      }
    end
  end

  # Append several fields with one rebuild of the document buffer.
  def append(&)
    append_with_builder do |builder|
      yield builder
    end
  end

  private def append_with_builder(&)
    io = IO::Memory.new(@data.size)
    io.write @data[4...-1]
    builder = Builder.new(io)
    yield builder
    @data = builder.to_bson
    self
  end

  # Append the contents of another BSON instance.
  #
  # ```
  # bson = BSON.new
  # other_bson = BSON.new({key: "value", key2: "value2"})
  # bson.append(other_bson)
  # puts bson.to_json # => {"key":"value","key2":"value2"}
  # ```
  def append(other : BSON)
    # [Performance] Append raw bytes directly, avoiding field decoding/encoding overhead
    io = IO::Memory.new(@data.size + other.size - 5)
    io.write @data[4...-1]
    io.write other.data[4...-1]
    builder = Builder.new(io)
    @data = builder.to_bson
  end

  # Clears the BSON instance.
  def clear
    @data = empty_document_bytes
  end

  # Return the element with the given key, or `nil` if the key is not present.
  #
  # ```
  # bson = BSON.new({key: "value"})
  # puts bson["key"]?  # => "value"
  # puts bson["nope"]? # => nil
  # ```
  def []?(key : String | ::Symbol) : Value?
    fetch(key)[0]
  end

  # Return the element with the given key.
  #
  # NOTE: Will raise if the key is not found.
  #
  # ```
  # bson = BSON.new({ key: "value" })
  # puts bson["key"] # =>"value"
  # puts bson["nope"] # => Unhandled exception: Missing bson key: nope (KeyError)
  def [](key : String | ::Symbol) : Value
    value, found = fetch(key)
    raise KeyError.new("Missing bson key: #{key}") unless found
    value
  end

  # Returns `true` when key given by *key* exists, otherwise `false`.
  def has_key?(key : String | ::Symbol) : Bool
    _, found = fetch(key)
    found
  end

  # Returns `true` if the BSON is empty.
  def empty? : Bool
    size == 5
  end

  # Traverses the depth of a structure and returns the value, otherwise raises.
  def dig(key : String | ::Symbol, *subkeys)
    if (value = self[key]) && value.is_a? BSON
      return value.dig(*subkeys)
    end
    raise KeyError.new("BSON value not diggable for key: #{key.inspect}")
  end

  # Traverses the depth of a structure and returns the value.
  # Returns `nil` if not found.
  def dig?(key : String | ::Symbol, *subkeys)
    if (value = self[key]?) && value.is_a? BSON
      value.dig?(*subkeys)
    end
  end

  # :nodoc:
  def dig(key : String | ::Symbol)
    self[key]
  end

  # :nodoc:
  def dig?(key : String | ::Symbol)
    self[key]?
  end

  private def fetch(key : String | ::Symbol)
    key = key.to_s
    pointer = @data.to_unsafe
    size = pointer.as(Pointer(Int32)).value
    pos = 4

    loop do
      break if (pointer + pos).value == 0

      # Element code
      code = Element.new((pointer + pos).value)
      pos += 1

      # [Performance] Compare raw string bytes via LibC to avoid allocating Strings for skipped fields
      key_size = key.bytesize
      if (pointer + pos + key_size).value == 0 && LibC.memcmp(pointer + pos, key.to_unsafe, key_size) == 0
        pos += key_size + 1
        _, data = Decoder.decode_field!(pointer, pos, {code, key}, max_pos: size)
        return {data[1], true}
      else
        # [Performance] Fast skip for non-matching fields
        pos += LibC.strlen(pointer + pos) + 1
        pos = Decoder.skip_field(code, pointer, pos, max_pos: size)
      end
    end

    return {nil, false}
  end

  # Compare with another BSON value.
  #
  # ```
  # puts BSON.new({a: 1}) <=> BSON.new({a: 1}) # => 0
  # puts BSON.new({a: 1}) <=> BSON.new({b: 2}) # => -1
  # ```
  def <=>(other : BSON)
    self.data <=> other.data
  end

  # Yield each key/value pair to the block.
  #
  # NOTE: Underlying BSON code as well as the binary subtype are also yielded to the block as additional arguments.
  #
  # ```
  # BSON.new({
  #   a: 1,
  #   b: "2",
  #   c: Slice[0_u8, 1_u8, 2_u8],
  # }).each { |(key, value, code, binary_subtype)|
  #   puts "#{key} => #{value}, code: #{code}, subtype: #{binary_subtype}"
  # # a => 1, code: Int32, subtype:
  # # b => 2, code: String, subtype:
  # # c => Bytes[0, 1, 2], code: Binary, subtype: Generic
  # }
  # ```
  def each(&block : Item -> _)
    pointer = @data.to_unsafe
    size = pointer.as(Pointer(Int32)).value
    pos = 4

    loop do
      if (pointer + pos).value == 0x00
        raise Error.new("Invalid BSON size.") if pos != size - 1
        break
      end
      raise Error.new("Invalid BSON size.") if pos >= size

      new_pos, data = Decoder.decode_field!(pointer, pos, max_pos: size)
      pos = new_pos

      yield data
    end
  end

  # Returns an Iterator over each key/value pair.
  def each
    Iterator.new(self)
  end

  private struct Iterator
    include ::Iterator(Item)

    @data : Bytes
    @pos = 4

    def initialize(bson : BSON)
      # [Performance] BSON fields are immutable during iteration, removing heap allocation clone
      @data = bson.data
    end

    def next
      pointer = @data.to_unsafe

      return Iterator::Stop::INSTANCE if (pointer + @pos).value == 0

      new_pos, data = Decoder.decode_field!(pointer, @pos, max_pos: @data.size)
      @pos = new_pos

      data
    end
  end

  # Returns a Hash representation.
  #
  # NOTE: This function is recursive and will convert nested BSON to hash objects.
  #
  # ```
  # bson = BSON.new({
  #   a: 1,
  #   b: "2",
  #   c: {
  #     d: 1,
  #   },
  # })
  # pp bson.to_h # => {"a" => 1, "b" => "2", "c" => { "d" => 1}}
  # ```
  def to_h
    hash = Hash(String, RecursiveValue).new
    self.each { |(key, value, code)|
      value = value.as(RecursiveValue)
      if value.is_a? BSON
        if code.array?
          hash[key] = value.to_h_array
        else
          hash[key] = value.to_h
        end
      else
        hash[key] = value
      end
    }
    hash
  end

  protected def to_h_array
    self.map { |_, value, code|
      value = value.as(RecursiveValue)
      if value.is_a? BSON
        if code.array?
          value.to_h_array
        else
          value.to_h
        end
      else
        value
      end
    }
  end

  # Re-encode this document from decoded values.
  #
  # Degenerate array keys become 0, 1, 2, ... and regex options become
  # alphabetical. Used to check native BSON round-trips.
  def canonicalize : BSON
    canonicalize(as_array: false)
  end

  protected def canonicalize(as_array : Bool) : BSON
    builder = Builder.new
    index = 0
    self.each { |key, value, code, subtype|
      out_key = if as_array
                  str_index = index < 128 ? Builder::STATIC_INDICES.unsafe_fetch(index) : index.to_s
                  index += 1
                  str_index
                else
                  key
                end

      case code
      when Element::Array
        builder.append_array(out_key, value.as(BSON).canonicalize(as_array: true))
      when Element::Document
        builder[out_key] = value.as(BSON).canonicalize(as_array: false)
      when Element::Binary
        if value.is_a?(UUID)
          builder[out_key] = value
        elsif value.is_a?(Bytes)
          builder[out_key] = Binary.new(subtype || Binary::SubType::Generic, value)
        else
          raise "Invalid binary value"
        end
      else
        builder[out_key] = value
      end
    }
    BSON.view(builder.to_bson)
  end

  # Validate that the BSON is well-formed.
  #
  # ```
  # bson = BSON.new("140000000461000D0000001030000A0000000000".hexbytes)
  # bson.validate!
  # # => Unhandled exception: Invalid BSON (overflow) (Exception)
  # ```
  def validate!
    # [Performance] Avoid unnecessary tuple allocations during validation
    self.each { }
  end
end
