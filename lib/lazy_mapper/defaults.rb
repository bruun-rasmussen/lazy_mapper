# frozen_string_literal: true

require 'bigdecimal'
require 'bigdecimal/util'
require 'time'

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
  # Default values for built-in value types
  #
  DEFAULT_VALUES = {
    String     => '',
    Integer    => 0,
    Numeric    => 0,
    Float      => 0.0,
    BigDecimal => BigDecimal(0),
    Array      => []
  }.freeze
end
