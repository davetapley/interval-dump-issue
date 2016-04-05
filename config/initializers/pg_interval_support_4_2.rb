# https://gist.github.com/Envek/7077bfc36b17233f60ad#file-pg_interval_support_4_2-rb
#
# Enables PostgreSQL interval datatype support (as ActiveSupport::Duration) in Ruby on Rails 4.2.
# This initializer is extracted from next pull requests:
#  * https://github.com/rails/rails/pull/16917
#  * https://github.com/rails/rails/pull/16919

require 'active_support/duration'

module ActiveSupport
  class Duration

    def inspect #:nodoc:
      parts.
        reduce(::Hash.new(0)) { |h,(l,r)| h[l] += r; h }.
        sort_by {|unit,  _ | [:years, :months, :weeks, :days, :hours, :minutes, :seconds].index(unit)}.
        map     {|unit, val| "#{val} #{val == 1 ? unit.to_s.chop : unit.to_s}"}.
        to_sentence(:locale => :en)
    end

    # Parses a string formatted according to ISO 8601 Duration into the hash .
    #
    # See http://en.wikipedia.org/wiki/ISO_8601#Durations
    # Parts of code are taken from ISO8601 gem by Arnau Siches (@arnau).
    # This parser isn't so strict and allows negative parts to be present in pattern.
    class ISO8601DurationParser
      attr_reader :parts

      class ParsingError < ::StandardError; end

      def initialize(iso8601duration)
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
            $/x) || raise(ParsingError.new("Invalid ISO 8601 duration: #{iso8601duration}"))
        sign = match[:sign] == '-' ? -1 : 1
        @parts = match.names.zip(match.captures).reject{|_k,v| v.nil? }.map do |k, v|
          value = /\d+[\.,]\d+/ =~ v ? v.sub(',', '.').to_f : v.to_i
          [ k.to_sym, sign * value ]
        end
        @parts = ::Hash[parts].slice(:years, :months, :weeks, :days, :hours, :minutes, :seconds)
        # Validate that is not empty duration or time part is empty if 'T' marker present
        if parts.empty? || (match[:time].present? && match[:time][1..-1].empty?)
          raise ParsingError.new("Invalid ISO 8601 duration: #{iso8601duration} (empty duration or empty time part)")
        end
        # Validate fractions (standart allows only last part to be fractional)
        fractions = parts.values.reject(&:zero?).select { |a| (a % 1) != 0 }
        unless fractions.empty? || (fractions.size == 1 && fractions.last == parts.values.reject(&:zero?).last)
          raise ParsingError.new("Invalid ISO 8601 duration: #{iso8601duration} (only last part can be fractional)")
        end
      end

    end

    # Creates a new Duration from string formatted according to ISO 8601 Duration.
    #
    # See http://en.wikipedia.org/wiki/ISO_8601#Durations
    # This method allows negative parts to be present in pattern.
    # If invalid string is provided, it will raise +ActiveSupport::Duration::ISO8601DurationParser::ParsingError+.
    def self.parse!(iso8601duration)
      parts = ISO8601DurationParser.new(iso8601duration).parts
      time  = ::Time.now
      new(time.advance(parts) - time, parts)
    end

    # Creates a new Duration from string formatted according to ISO 8601 Duration.
    #
    # See http://en.wikipedia.org/wiki/ISO_8601#Durations
    # This method allows negative parts to be present in pattern.
    # If invalid string is provided, nil will be returned.
    def self.parse(iso8601duration)
      parse!(iso8601duration)
    rescue ISO8601DurationParser::ParsingError
      nil
    end

    # Build ISO 8601 Duration string for this duration.
    # The +precision+ parameter can be used to limit seconds' precision of duration.
    def iso8601(precision=nil)
      output, sign = 'P', ''
      parts = normalized_parts
      # If all parts are negative - let's output negative duration
      if parts.values.compact.all?{|v| v < 0 }
        sign = '-'
        parts = parts.inject({}) {|p,(k,v)| p[k] = -v; p }
      end
      # Building output string
      output << "#{parts[:years]}Y"   if parts[:years]
      output << "#{parts[:months]}M"  if parts[:months]
      output << "#{parts[:weeks]}W"   if parts[:weeks]
      output << "#{parts[:days]}D"    if parts[:days]
      time = ''
      time << "#{parts[:hours]}H"     if parts[:hours]
      time << "#{parts[:minutes]}M"   if parts[:minutes]
      if parts[:seconds]
        time << "#{sprintf(precision ? "%0.0#{precision}f" : '%g', parts[:seconds])}S"
      end
      output << "T#{time}"  if time.present?
      "#{sign}#{output}"
    end

    # Return duration's parts summarized (as they can become repetitive due to addition, etc)
    # Also removes zero parts as not significant
    def normalized_parts
      parts = self.parts.inject(::Hash.new(0)) do |p,(k,v)|
        p[k] += v  unless v.zero?
        p
      end
      parts.default = nil
      parts
    end

  end
end

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module OID # :nodoc:
        class Interval < Type::Value # :nodoc:
          def type
            :interval
          end

          def type_cast_from_database(value)
            if value.kind_of? ::String
              ::ActiveSupport::Duration.parse!(value)
            else
              super
            end
          end

          def type_cast_from_user(value)
            type_cast_from_database(value)
          rescue ::ActiveSupport::Duration::ISO8601DurationParser::ParsingError
            value # Allow user to supply raw string values in another formats supported by PostgreSQL
          end

          def type_cast_for_database(value)
            case value
              when ::ActiveSupport::Duration
                value.iso8601(self.precision)
              when ::Numeric
                time = ::Time.now
                duration = ::ActiveSupport::Duration.new(time.advance(seconds: value) - time, seconds: value)
                duration.iso8601(self.precision)
              else
                super
            end
          end

          def type_cast_for_schema(value)
            "\"#{value.to_s}\""
          end
        end
      end
    end
  end
end

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module ColumnMethods
        def interval(name, options = {})
          column(name, :interval, options)
        end
      end
    end
  end
end

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module SchemaStatements
        alias_method :type_to_sql_without_interval, :type_to_sql
        def type_to_sql(type, limit = nil, precision = nil, scale = nil)
          case type.to_s
          when 'interval'
            return super unless precision

            case precision
              when 0..6; "interval(#{precision})"
              else raise(ActiveRecordError, "No interval type has precision of #{precision}. The allowed range of precision is from 0 to 6")
            end
          else
            type_to_sql_without_interval(type, limit, precision, scale)
          end
        end
      end
    end
  end
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter::NATIVE_DATABASE_TYPES[:interval] = { name: 'interval'}

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.class_eval do

  define_method :initialize_type_map_with_interval do |m|
    initialize_type_map_without_interval(m)
    m.register_type 'interval' do |_, _, sql_type|
      precision = extract_precision(sql_type)
      ::ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Interval.new(precision: precision)
    end
  end
  alias_method_chain :initialize_type_map, :interval

  define_method :configure_connection_with_interval do
    configure_connection_without_interval
    execute('SET intervalstyle = iso_8601', 'SCHEMA')
  end
  alias_method_chain :configure_connection, :interval

end
