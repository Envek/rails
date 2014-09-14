require 'active_support/proxy_object'
require 'active_support/core_ext/array/conversions'
require 'active_support/core_ext/object/acts_like'

module ActiveSupport
  # Provides accurate date and time measurements using Date#advance and
  # Time#advance, respectively. It mainly supports the methods on Numeric.
  #
  #   1.month.ago       # equivalent to Time.now.advance(months: -1)
  class Duration < ProxyObject
    attr_accessor :value, :parts

    def initialize(value, parts) #:nodoc:
      @value, @parts = value, parts
    end

    # Adds another Duration or a Numeric to this Duration. Numeric values
    # are treated as seconds.
    def +(other)
      if Duration === other
        Duration.new(value + other.value, @parts + other.parts)
      else
        Duration.new(value + other, @parts + [[:seconds, other]])
      end
    end

    # Subtracts another Duration or a Numeric from this Duration. Numeric
    # values are treated as seconds.
    def -(other)
      self + (-other)
    end

    def -@ #:nodoc:
      Duration.new(-value, parts.map { |type,number| [type, -number] })
    end

    def is_a?(klass) #:nodoc:
      Duration == klass || value.is_a?(klass)
    end
    alias :kind_of? :is_a?

    def instance_of?(klass) # :nodoc:
      Duration == klass || value.instance_of?(klass)
    end

    # Returns +true+ if +other+ is also a Duration instance with the
    # same +value+, or if <tt>other == value</tt>.
    def ==(other)
      if Duration === other
        other.value == value
      else
        other == value
      end
    end

    def eql?(other)
      other.is_a?(Duration) && self == other
    end

    def self.===(other) #:nodoc:
      other.is_a?(Duration)
    rescue ::NoMethodError
      false
    end

    # Calculates a new Time or Date that is as far in the future
    # as this Duration represents.
    def since(time = ::Time.current)
      sum(1, time)
    end
    alias :from_now :since

    # Calculates a new Time or Date that is as far in the past
    # as this Duration represents.
    def ago(time = ::Time.current)
      sum(-1, time)
    end
    alias :until :ago

    def inspect #:nodoc:
      parts.
        reduce(::Hash.new(0)) { |h,(l,r)| h[l] += r; h }.
        sort_by {|unit,  _ | [:years, :months, :weeks, :days, :hours, :minutes, :seconds].index(unit)}.
        map     {|unit, val| "#{val} #{val == 1 ? unit.to_s.chop : unit.to_s}"}.
        to_sentence(:locale => :en)
    end

    def as_json(options = nil) #:nodoc:
      to_i
    end

    class ISO8601ParsingError < ::StandardError; end

    # Creates a new Duration from string formatted according to ISO 8601 Duration.
    #
    # See http://en.wikipedia.org/wiki/ISO_8601#Durations
    # Parts of code are taken from ISO8601 gem by Arnau Siches (@arnau).
    # This method isn't so strict and allows negative parts to be present in pattern.
    def self.parse(iso8601duration)
      match = iso8601duration.match(/^
        (?<sign>\+|-)?
        P(?:
          (?:
            (?:(?<years>-?\d+(?:[,.]\d+)?)Y)?
            (?:(?<months>-?\d+(?:[.,]\d+)?)M)?
            (?:(?<days>-?\d+(?:[.,]\d+)?)D)?
            (?<time>T
              (?:(?<hours>-?\d+(?:[.,]\d+)?)H)?
              (?:(?<minutes>-?\d+(?:[.,]\d+)?)M)?
              (?:(?<seconds>-?\d+(?:[.,]\d+)?)S)?
            )?
          ) |
          (?<weeks>-?\d+(?:[.,]\d+)?W)
        ) # Duration
      $/x) || raise(ISO8601ParsingError.new("Invalid ISO 8601 duration: #{iso8601duration}"))
      sign = match[:sign] == '-' ? -1 : 1
      parts = match.names.zip(match.captures).reject{|_k,v| v.nil? }.map do |k, v|
        value = /\d+[\.,]\d+/ =~ v ? v.sub(',', '.').to_f : v.to_i
        [ k.to_sym, sign * value ]
      end
      parts = ::Hash[parts].slice(:years, :months, :weeks, :days, :hours, :minutes, :seconds)
      # Validate that is not empty duration or time part is empty if 'T' marker present
      if parts.empty? || (match[:time].present? && match[:time][1..-1].empty?)
        raise ISO8601ParsingError.new("Invalid ISO 8601 duration: #{iso8601duration} (empty duration or empty time part)")
      end
      # Validate fractions (standart allows only last part to be fractional)
      fractions = parts.values.reject(&:zero?).select { |a| (a % 1) != 0 }
      unless fractions.empty? || (fractions.size == 1 && fractions.last == parts.values.reject(&:zero?).last)
        raise ISO8601ParsingError.new("Invalid ISO 8601 duration: #{iso8601duration} (only last part can be fractional)")
      end
      # Initialize new duration
      time  = ::Time.now
      new(time.advance(parts) - time, parts)
    end

    # Build ISO 8601 Duration string for this duration.
    # The +precision+ parameter can be used to limit seconds' precision of duration.
    def iso8601(precision=nil)
      output = 'P'
      # First, trying to summarize duration parts (they can be repetitive)
      parts = self.parts.inject(::Hash.new(0)) {|p,(k,v)| p[k] += v; p }
      # If all parts are negative - let's output negative duration
      if parts.values.select(&:present?).all?{|v| v < 0 }
        sign = '-'
        parts = parts.inject(::Hash.new(0)) {|p,(k,v)| p[k] = -v; p }
      end
      # Building output string
      output << "#{parts[:years]}Y"   if parts[:years].nonzero?
      output << "#{parts[:months]}M"  if parts[:months].nonzero?
      output << "#{parts[:weeks]}W"   if parts[:weeks].nonzero?
      output << "#{parts[:days]}D"    if parts[:days].nonzero?
      time = ''
      time << "#{parts[:hours]}H"   if parts[:hours].nonzero?
      time << "#{parts[:minutes]}M" if parts[:minutes].nonzero?
      if parts[:seconds].nonzero?
        time << "#{sprintf(precision ? "%0.0#{precision}f" : '%g', parts[:seconds])}S"
      end
      output << "T#{time}"  if time.present?
      "#{sign}#{output}"
    end

    protected

      def sum(sign, time = ::Time.current) #:nodoc:
        parts.inject(time) do |t,(type,number)|
          if t.acts_like?(:time) || t.acts_like?(:date)
            if type == :seconds
              t.since(sign * number)
            else
              t.advance(type => sign * number)
            end
          else
            raise ::ArgumentError, "expected a time or date, got #{time.inspect}"
          end
        end
      end

    private

      # We define it as a workaround to Ruby 2.0.0-p353 bug.
      # For more information, check rails/rails#13055.
      # Remove it when we drop support for 2.0.0-p353.
      def ===(other) #:nodoc:
        value === other
      end

      def method_missing(method, *args, &block) #:nodoc:
        value.send(method, *args, &block)
      end
  end
end
