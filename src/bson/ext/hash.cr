class Hash(K, V)
  def self.from_bson(bson : BSON::Value) : self
    raise "Invalid BSON" unless bson.is_a? BSON

    {% begin %}
    {% types = V.union_types %}

    {% if types.select(&.<=(Hash)).size > 1 %}
    {% raise "Unable to deserialize #{@type.id}. Can only have one Hash value type." %}
    {% end %}

    {% if types.select(&.<=(Array)).size > 1 %}
    {% raise "Unable to deserialize #{@type.id}. Can only have one Array value type." %}
    {% end %}

    hash = self.new

    bson.each do |(k, v, code, _)|
      case {v, code}

      {% htyp = types.find(&.<=(Hash)) %}
      {% if htyp %}
      when {BSON, BSON::Element::Document}
        hash[k] = {{ htyp }}.from_bson(v)
      {% end %}

      {% atyp = types.find(&.<=(Array)) %}
      {% if atyp %}
      when {BSON, BSON::Element::Array}
        hash[k] = {{ atyp }}.from_bson(v)
      {% end %}

      # Time/DateTime and Regex/BSON::Regex each emit two `when` branches.
      # Inspect the whole union first so Hash(..., BSON::Value) does not emit the same `when` twice.
      {% has_time = types.any? { |t| t <= Time } %}
      {% has_date_time = types.any? { |t| t <= BSON::DateTime } %}
      {% has_regex = types.any? { |t| t <= ::Regex } %}
      {% has_bson_regex = types.any? { |t| t <= BSON::Regex } %}
      {% if has_time && has_date_time %}
      when {BSON::DateTime, _}
        hash[k] = v.as(BSON::DateTime)
      when {Time, _}
        hash[k] = v.as(Time)
      {% elsif has_time %}
      when {BSON::DateTime, _}
        hash[k] = v.as(BSON::DateTime).to_time
      when {Time, _}
        hash[k] = v.as(Time)
      {% elsif has_date_time %}
      when {BSON::DateTime, _}
        hash[k] = v.as(BSON::DateTime)
      when {Time, _}
        hash[k] = BSON::DateTime.new(v.as(Time))
      {% end %}
      {% if has_regex && has_bson_regex %}
      when {BSON::Regex, _}
        hash[k] = v.as(BSON::Regex)
      when {::Regex, _}
        hash[k] = v.as(::Regex)
      {% elsif has_regex %}
      when {BSON::Regex, _}
        hash[k] = v.as(BSON::Regex).to_regex
      when {::Regex, _}
        hash[k] = v.as(::Regex)
      {% elsif has_bson_regex %}
      when {BSON::Regex, _}
        hash[k] = v.as(BSON::Regex)
      when {::Regex, _}
        hash[k] = BSON::Regex.new(v.as(::Regex))
      {% end %}
      {% for typ in types.uniq %}
        {% if typ <= Hash || typ <= Array || typ <= Time || typ <= BSON::DateTime || typ <= ::Regex || typ <= BSON::Regex %}

        {% elsif (typ <= BSON::Serializable || typ.class.has_method? :from_bson) %}
        when { BSON, _ }
          hash[k] = {{ typ }}.from_bson(v)

        {% else %}
        when { {{ typ }}, _ }
          hash[k] = v.as({{typ}})
        {% end %}
      {% end %}

      {% if V <= Number %}
        {% ntyp = types.find(&.<=(Number)) %}
        {% if ntyp %}
        when {Number, _}
          hash[k] = {{ ntyp }}.new(v)
        {% end %}
      {% end %}
      else
        raise Exception.new "Unable to deserialize key '#{k}' for hash '{{@type.id}}'."
      end
    end

    hash
    {% end %}
  end
end
