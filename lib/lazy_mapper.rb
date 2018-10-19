require 'bigdecimal'
require 'bigdecimal/util'
require 'time'

#
# Wraps a Hash or Hash-like data structure of primitive values and lazily maps
# its attributes to semantically rich domain objects using either a set of
# default mappers (for Ruby's built-in value types), or custom mappers which
# can be added either at the class level or at the instance level.
#
# Example:
#     class Foo < LazyMapper
#       one :id, Integer, from: 'xmlId'
#       one :created_at, Time
#       one :amount, Money, map: Money.method(:parse)
#       many :users, User, map: ->(u) { User.new(u) }
#     end
#
class LazyMapper

  #
  # Default mappings for built-in types
  #
  DEFAULT_MAPPINGS = {
    Object     => :itself.to_proc,
    String     => :to_s.to_proc,
    Integer    => :to_i.to_proc,
    BigDecimal => :to_d.to_proc,
    Float      => :to_f.to_proc,
    Symbol     => :to_sym.to_proc,
    Hash       => :to_h.to_proc,
    Time       => Time.method(:iso8601),
    Date       => Date.method(:parse),
    URI        => URI.method(:parse)
  }.freeze

  #
  # Adds (or overrides) a default type for a given type
  #
  def self.default_value_for type, value
    default_values[type] = value
  end

  def self.default_values
    @default_values ||= DEFAULT_VALUES
  end

  #
  # Default values for built-in value types
  #
  DEFAULT_VALUES = {
    String     => '',
    Integer    => 0,
    Numeric    => 0,
    Float      => 0.0,
    BigDecimal => BigDecimal.new('0'),
    Array      => []
  }.freeze

  #
  # Adds a mapper for a give type
  #
  def self.mapper_for(type, mapper)
    mappers[type] = mapper
  end

  def self.mappers
    @mappers ||= DEFAULT_MAPPINGS
  end

  def self.inherited(klass)
    klass.instance_variable_set IVAR[:mappers], self.mappers.dup
    klass.instance_variable_set IVAR[:default_values], self.default_values.dup
  end

  def mappers
    @mappers ||= self.class.mappers
  end

  IVAR = lambda { |name| # :nodoc:
    name_as_str = name.to_s
    name_as_str = name_as_str[0...-1] if name_as_str[-1] == '?'

    ('@' + name_as_str).freeze
  }

  WRITER = -> name { (name.to_s.delete('?') + '=').to_sym }

  #
  # Creates a new instance by giving a Hash of attribues.
  #
  # Attribute values are type checked according to how they were defined.
  #
  # Fails with +TypeError+, if a value doesn't have the expected type.
  #
  # == Example
  #
  #     Foo.new :id => 42,
  #       :created_at => Time.parse("2015-07-29 14:07:35 +0200"),
  #       :amount => Money.parse("$2.00"),
  #       :users => [
  #         User.new("id" => 23, "name" => "Adam"),
  #         User.new("id" => 45, "name" => "Ole"),
  #         User.new("id" => 66, "name" => "Anders"),
  #         User.new("id" => 91, "name" => "Kristoffer)
  #       ]

  def initialize(values = {})
    @mappers = {}
    values.each do |name, value|
      send(WRITER[name], value)
    end
  end

  #
  # Create a new instance by giving a Hash of unmapped attributes.
  #
  # The keys in the Hash are assumed to be camelCased strings.
  #
  # == Arguments
  #
  # +unmapped_data+ - The unmapped data as a Hash(-like object). Must respond to #to_h.
  # Keys are assumed to be camelCased string
  #
  # +mappers:+ - Optional instance-level mappers.
  # Keys can either be classes or symbols corresponding to named attributes.
  #
  #
  # == Example
  #
  #     Foo.from({
  #       "xmlId" => 42,
  #       "createdAt" => "2015-07-29 14:07:35 +0200",
  #       "amount" => "$2.00",
  #       "users" => [
  #         { "id" => 23, "name" => "Adam" },
  #         { "id" => 45, "name" => "Ole" },
  #         { "id" => 66, "name" => "Anders" },
  #         { "id" => 91, "name" => "Kristoffer" } ]},
  #       mappers: {
  #         :amount => -> x { Money.new(x) },
  #         User    => User.method(:new) })
  #
  def self.from unmapped_data, mappers: {}
    return nil if unmapped_data.nil?
    fail TypeError, "#{ unmapped_data.inspect } is not a Hash" unless unmapped_data.respond_to? :to_h
    instance = new
    instance.send :unmapped_data=, unmapped_data.to_h
    instance.send :mappers=, mappers
    instance
  end

  def self.from_json *args, &block
    warn "#{ self }.from_json is deprecated. Use #{ self }.from instead."
    from *args, &block
  end

  def self.attributes
    @attributes ||= {}
  end

  #
  # Defines an attribute and creates a reader and a writer for it.
  # The writer verifies the type of it's supplied value.
  #
  # == Arguments
  #
  # +name+ - The name of the attribue
  #
  # +type+ - The type of the attribute. If the wrapped value is already of that type, the mapper is bypassed.
  # If the type is allowed be one of several, use an Array to to specify which ones
  #
  # +from:+ - Specifies the name of the wrapped value in the JSON object. Defaults to camelCased version of +name+.
  #
  # +map:+ - Specifies a custom mapper to apply to the wrapped value.
  # If unspecified, it defaults to the default mapper for the specified +type+ or simply the identity mapper
  # if no default mapper exists.
  #
  # +default:+ - The default value to use, if the wrapped value is not present in the wrapped JSON object.
  #
  # +allow_nil:+ - If true, allows the mapped value to be nil. Defaults to true.
  #
  # == Example
  #
  #    class Foo < LazyMapper
  #      one :boss, Person, from: "supervisor", map: ->(p) { Person.new(p) }
  #      one :weapon, [BladedWeapon, Firearm], default: Sixshooter.new
  #      # ...
  #    end
  #
  def self.one(name, type, from: map_name(name), allow_nil: true, **args)

    ivar = IVAR[name]

    # Define writer
    define_method(WRITER[name]) { |val|
      check_type! val, type, allow_nil: allow_nil
      instance_variable_set(ivar, val)
    }

    # Define reader
    define_method(name) {
      memoize(name, ivar) {
        unmapped_value = unmapped_data[from]
        mapped_value(name, unmapped_value, type, **args)
      }
    }

    attributes[name] = type
  end

  #
  # Converts a value to +true+ or +false+ according to its truthyness
  #
  TO_BOOL = -> b { !!b }

  #
  # Defines an boolean attribute
  #
  # == Arguments
  #
  # +name+ - The name of the attribue
  #
  # +from:+ - Specifies the name of the wrapped value in the JSON object.
  # Defaults to camelCased version of +name+.
  #
  # +map:+ - Specifies a custom mapper to apply to the wrapped value. Must be a Callable.
  # Defaults to TO_BOOL if unspecified.
  #
  # +default:+ The default value to use if the value is missing. False, if unspecified
  #
  # == Example
  #
  #    class Foo < LazyMapper
  #      is :green?, from: "isGreen", map: ->(x) { !x.zero? }
  #      # ...
  #    end
  #
  def self.is name, from: map_name(name), map: TO_BOOL, default: false
    one name, [TrueClass, FalseClass], from: from, allow_nil: false, map: map, default: default
  end

  singleton_class.send(:alias_method, :has, :is)

  #
  # Defines a collection attribute
  #
  # == Arguments
  #
  # +name+ - The name of the attribute
  #
  # +type+ - The type of the elements in the collection.
  #
  # +from:+ - Specifies the name of the wrapped array in the unmapped data.
  # Defaults to camelCased version of +name+.
  #
  # +map:+ - Specifies a custom mapper to apply to each elements in the wrapped collection.
  # If unspecified, it defaults to the default mapper for the specified +type+ or simply the identity mapper
  # if no default mapper exists.
  #
  # +default:+ - The default value to use, if the unmapped value is missing.
  #
  # == Example
  #
  #    class Bar < LazyMapper
  #      many :underlings, Person, from: "serfs", map: ->(p) { Person.new(p) }
  #      # ...
  #    end
  #
  def self.many(name, type, from: map_name(name), **args)

    # Define setter
    define_method(WRITER[name]) { |val|
      check_type! val, Enumerable, allow_nil: false
      instance_variable_set(IVAR[name], val)
    }

    # Define getter
    define_method(name) {
      memoize(name) {
        unmapped_value = unmapped_data[from]
        if unmapped_value.is_a? Array
          unmapped_value.map { |v| mapped_value(name, v, type, **args) }
        else
          mapped_value name, unmapped_value, Array, **args
        end
      }
    }
  end

  #
  # Adds an instance-level type mapper
  #
  def add_mapper_for(type, &block)
    mappers[type] = block
  end

  def inspect
    @__under_inspection__ ||= 0
    return "<#{ self.class.name } ... >" if @__under_inspection__ > 0
    @__under_inspection__ += 1
    attributes = self.class.attributes
    attributes = self.class.superclass.attributes.merge attributes if self.class.superclass.respond_to? :attributes
    present_attributes = attributes.keys.each_with_object({}) { |name, memo|
      value = self.send name
      memo[name] = value unless value.nil?
    }
    "<#{ self.class.name } #{ present_attributes.map { |k, v| k.to_s + ': ' + v.inspect }.join(', ') } >"
    res = "<#{ self.class.name } #{ present_attributes.map { |k, v| k.to_s + ': ' + v.inspect }.join(', ') } >"
    @__under_inspection__ -= 1
    res
  end

  protected

  #
  # Defines how to map an attribute name
  # to the corresponding name in the unmapped
  # JSON object.
  #
  # Defaults to CAMELIZE
  #
  def self.map_name(name)
    CAMELIZE[name]
  end

  private

  attr_writer :unmapped_data
  attr_writer :mappers

  def unmapped_data
    @unmapped_data ||= {}
  end

  def mapping_for(name, type)
    mappers[name] || mappers[type] || self.class.mappers[type]
  end

  def default_value(type)
    self.class.default_values[type]
  end

  def mapped_value(name, unmapped_value, type, map: mapping_for(name, type), default: default_value(type))
    if unmapped_value.nil?
      # Duplicate to prevent accidental sharing between instances
      default.dup
    else
      fail ArgumentError, "missing mapper for #{ name } (#{ type }). Unmapped value: #{ unmapped_value.inspect }" if map.nil?
      result = map.arity > 1 ? map.call(unmapped_value, self) : map.call(unmapped_value)
      result
    end
  end

  def check_type! value, type, allow_nil:
    permitted_types = allow_nil ? Array(type) + [ NilClass ] : Array(type)
    fail TypeError.new "#{ self.class.name }: #{ value.inspect } is a #{ value.class } but was supposed to be a #{ humanize_list permitted_types, conjunction: ' or ' }" unless permitted_types.any? value.method(:is_a?)
  end

  # [1,2,3] -> "1, 2 and 3"
  # [1, 2]  -> "1 and 2"
  # [1]     -> "1"
  def humanize_list list, separator: ', ', conjunction: ' and '
    *all_but_last, last = list
    return last if all_but_last.empty?
    [ all_but_last.join(separator), last ].join conjunction
  end

  def memoize name, ivar = IVAR[name]
    send WRITER[name], yield unless instance_variable_defined?(ivar)
    instance_variable_get(ivar)
  end

  SNAKE_CASE_PATTERN = /(_[a-z])/ # :nodoc:
  CAMELIZE = -> name { name.to_s.gsub(SNAKE_CASE_PATTERN) { |x| x[1].upcase }.delete('?') }
end
