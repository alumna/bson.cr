module BSON::Serializable
  macro included
    {% verbatim do %}

    # Allocate an instance and copies data from a BSON struct.
    #
    # ```
    # class User
    #   include BSON::Serializable
    #   property name : String
    # end
    #
    # data = BSON.new
    # data["name"] = "John"
    # User.new(data)
    # ```
    def initialize(bson : BSON)
      {% begin %}
        {% global_options = @type.annotations(BSON::Options) %}
        # [Simplicity] Access the last annotation directly instead of a meaningless reduce
        {% camelize = global_options.last && global_options.last[:camelize] %}

        {% for ivar in @type.instance_vars %}
          {% ann = ivar.annotation(BSON::Field) %}
          {% unless ann && ann[:ignore] %}
            %var{ivar.name} = uninitialized ::Union(typeof(@{{ ivar.name }}))
            %found{ivar.name} = false
          {% end %}
        {% end %}

        # [Performance] Traverse the BSON document exactly once (O(M)) instead of calling `fetch` for each property (O(N*M))
        bson.each do |key, bson_value, _code, _subtype|
          case key
          {% for ivar in @type.instance_vars %}
            {% ann = ivar.annotation(BSON::Field) %}
            {% unless ann && ann[:ignore] %}
              {% bson_key = ann && ann[:key] ? ann[:key].id : (camelize ? ivar.name.camelcase(lower: camelize == "lower") : ivar.name) %}
              {% types = ivar.type.union_types.select { |t| t != Nil } %}
              {% number_conversion_added = false %}
              when "{{ bson_key }}"
                %found{ivar.name} = true
                %var{ivar.name} = case bson_value
                {% for typ in types %}
                  {% if typ <= BSON::Serializable %}
                  when BSON
                    {{ typ }}.from_bson(bson_value)
                  {% elsif typ.class.has_method?(:from_bson) %}
                  when BSON, BSON::Value
                    {{ typ }}.from_bson(bson_value)
                  {% elsif typ <= Int || typ <= Float %}
                  when {{ typ }}
                    bson_value.as({{ typ }})
                  {% unless number_conversion_added %}
                  {% number_conversion_added = true %}
                  when Int, Float
                    {{ typ }}.new!(bson_value)
                  {% end %}
                  {% else %}
                  when {{ typ }}
                    bson_value.as({{ typ }})
                  {% end %}
                {% end %}
                else
                  raise Exception.new("Unable to deserialize key '{{bson_key}}' having value #{bson_value} of type #{bson_value.class} belonging to type '{{@type}}'. Expected type(s) {{types}}.")
                end
            {% end %}
          {% end %}
          end
        end

        {% for ivar in @type.instance_vars %}
          {% ann = ivar.annotation(BSON::Field) %}
          {% unless ann && ann[:ignore] %}
            if %found{ivar.name}
              @{{ ivar.name }} = %var{ivar.name}
            else
              {% if !ivar.type.nilable? && !ivar.has_default_value? %}
                raise Exception.new("Missing BSON attribute: '{{ ann && ann[:key] ? ann[:key].id : (camelize ? ivar.name.camelcase(lower: camelize == "lower") : ivar.name) }}' for '{{@type}}'.")
              {% elsif ivar.type.nilable? %}
                @{{ ivar.name }} = nil
              {% end %}
            end
          {% end %}
        {% end %}
      {% end %}
    end

    # NOTE: See `self.new`.
    def self.from_bson(bson : BSON)
      self.new(bson)
    end

    # Converts to a BSON representation.
    #
    # ```
    # user = User.new name: "John"
    # bson = user.to_bson
    # ```
    def to_bson(bson = BSON.new)
      {% begin %}
      {% global_options = @type.annotations(BSON::Options) %}
      # [Simplicity] Access the last annotation directly
      {% camelize = global_options.last && global_options.last[:camelize] %}
      {% for ivar in @type.instance_vars %}
        {% ann = ivar.annotation(BSON::Field) %}
        {% bson_key = ann && ann[:key] ? ann[:key].id : (camelize ? ivar.name.camelcase(lower: camelize == "lower") : ivar.name) %}
        {% unless ann && ann[:ignore] %}
          {% getter_names = [ivar.name + "?", ivar.name, ivar.name + "!"] %}
          {% getter_name = getter_names.find { |name| @type.has_method? name } %}
          {% if getter_name %}
            %val = self.{{ getter_name }}
            {% unless ann && ann[:emit_null] %}
              unless %val.nil?
            {% end %}
              # [Correctness] Dynamically check if the specific value responds to to_bson rather than relying on the first union type
              # [Performance/Simplicity] No redundant .try checking required since non-nil cases fall through cleanly
              if %val.responds_to?(:to_bson)
                bson["{{ bson_key }}"] = %val.to_bson
              else
                bson["{{ bson_key }}"] = %val
              end
            {% unless ann && ann[:emit_null] %}
              end
            {% end %}
          {% end %}
        {% end %}
      {% end %}
      {% end %}
      bson
    end

    {% end %}
  end
end
