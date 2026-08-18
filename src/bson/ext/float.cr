struct Float64
  # Serialize to a canonical extended json representation.
  #
  # NOTE: see https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
  def to_canonical_extjson(builder : JSON::Builder)
    builder.object {
      builder.string("$numberDouble")
      builder.string do |io|
        # Write the number into a stack buffer, then copy it while mapping 'e' to 'E'.
        buf = uninitialized UInt8[64]
        mem = IO::Memory.new(buf.to_slice, writable: true)
        to_s(mem)
        mem.to_slice[0, mem.pos].each do |byte|
          io.write_byte(byte == 0x65_u8 ? 0x45_u8 : byte)
        end
      end
    }
  end
end
