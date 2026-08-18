struct BSON
  # Raised when BSON bytes or Extended JSON cannot be read or do not match the spec.
  class Error < Exception
  end
end
