class Array(T)
  def self.from_bson(bson : BSON::Value) : self
    raise "Invalid BSON" unless bson.is_a? BSON
    {% begin %}
    {% types = T.union_types %}

    {% if types.select(&.<=(Hash)).size > 1 %}
    {% raise "Unable to deserialize #{@type.id}. Can only have one Hash value type." %}
    {% end %}

    {% if types.select(&.<=(Array)).size > 1 %}
    {% raise "Unable to deserialize #{@type.id}. Can only have one Array value type." %}
    {% end %}

    arr = self.new

    bson.each do |(_, v, code, _)|
      case {v, code}
      {% htyp = types.find(&.<=(Hash)) %}
      {% if htyp %}
      when {BSON, BSON::Element::Document}
        arr << {{ htyp }}.from_bson(v)
      {% end %}

      {% atyp = types.find(&.<=(Array)) %}
      {% if atyp %}
      when {BSON, BSON::Element::Array}
        arr << {{ atyp }}.from_bson(v)
      {% end %}

      # Time/DateTime and Regex/BSON::Regex each emit two `when` branches.
      # Inspect the whole union first so Array(BSON::Value) does not emit the same `when` twice.
      {% has_time = types.any? { |t| t <= Time } %}
      {% has_date_time = types.any? { |t| t <= BSON::DateTime } %}
      {% has_regex = types.any? { |t| t <= ::Regex } %}
      {% has_bson_regex = types.any? { |t| t <= BSON::Regex } %}
      {% if has_time && has_date_time %}
      when {BSON::DateTime, _}
        arr << v.as(BSON::DateTime)
      when {Time, _}
        arr << v.as(Time)
      {% elsif has_time %}
      when {BSON::DateTime, _}
        arr << v.as(BSON::DateTime).to_time
      when {Time, _}
        arr << v.as(Time)
      {% elsif has_date_time %}
      when {BSON::DateTime, _}
        arr << v.as(BSON::DateTime)
      when {Time, _}
        arr << BSON::DateTime.new(v.as(Time))
      {% end %}
      {% if has_regex && has_bson_regex %}
      when {BSON::Regex, _}
        arr << v.as(BSON::Regex)
      when {::Regex, _}
        arr << v.as(::Regex)
      {% elsif has_regex %}
      when {BSON::Regex, _}
        arr << v.as(BSON::Regex).to_regex
      when {::Regex, _}
        arr << v.as(::Regex)
      {% elsif has_bson_regex %}
      when {BSON::Regex, _}
        arr << v.as(BSON::Regex)
      when {::Regex, _}
        arr << BSON::Regex.new(v.as(::Regex))
      {% end %}
      {% for typ in types %}
        {% if typ <= Hash || typ <= Array || typ <= Time || typ <= BSON::DateTime || typ <= ::Regex || typ <= BSON::Regex %}
        {% elsif typ <= BSON::Serializable || typ.class.has_method? :from_bson %}
        when {BSON, _}
          arr << {{ typ }}.from_bson(v)
        {% else %}
        when { {{ typ }}, _}
          arr << v.as({{ typ }})
        {% end %}
      {% end %}

      {% if T <= Number %}
        {% ntyp = types.find(&.<=(Number)) %}
        {% if ntyp %}
        when {Number, _}
          arr << {{ ntyp }}.new(v)
        {% end %}
      {% end %}
      else
        raise Exception.new "Unable to deserialize BSON array '#{{{@type.stringify}}}'."
      end
    end

    arr

    {% end %}
  end
end
