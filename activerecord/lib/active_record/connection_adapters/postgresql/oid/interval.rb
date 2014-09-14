require 'active_support/duration'

module ActiveRecord
  module ConnectionAdapters
    module PostgreSQL
      module OID # :nodoc:
        class Interval < Type::Value # :nodoc:
          def type
            :interval
          end

          POSTGRES_FORMAT = /^ # Matches postgres format: -1 year -2 mons +3 days -04:05:06
            (?:(?<years>[\+\-]?\d+)\syear[s]?)?\s* # year part, like +3 years+
            (?:(?<months>[\+\-]?\d+)\smon[s]?)?\s* # month part, like +2 mons+
            (?:(?<days>[\+\-]?\d+)\sday[s]?)?\s*   # day part, like +5 days+
            (?:
              (?<timesign>[\+\-])?
              (?<hours>\d+):(?<minutes>\d+)(?::(?<seconds>\d+(?:\.\d+)?))?
            )?  # time part, like -00:00:00
          $/x

          POSTGRES_VERBOSE_FORMAT = /^@\s # Matches postgres verbose format: @ 1 year 2 mons -3 days 04:05:06 ago
            (?:(?<years>[\+\-]?\d+)\syear[s]?)?\s*    # year part, like +3 years+
            (?:(?<months>[\+\-]?\d+)\smon[s]?)?\s*    # month part, like +2 mons+
            (?:(?<days>[\+\-]?\d+)\sday[s]?)?\s*      # day part, like +5 days+
            (?:(?<hours>[\+\-]?\d+)\shour[s]?)?\s*    # hour part, like +2 hours+
            (?:(?<minutes>[\+\-]?\d+)\smin[s]?)?\s*   # minute part, like +36 minutes+
            (?:(?<seconds>[\+\-]?\d+(?:\.\d+)?)\ssec[s]?)?\s* # second part, like +5.5 seconds+
            (?<signword>ago)?
          $/x

          SQL_STANDARD_FORMAT = /^
            (?: # year or year and month part, like +99+ or +99-3+
              (?<yearmonthsign>[\+\-])?
              (?<years>\d+)(?:-(?<months>\d+))?
            )?\s*
            (?:
              (?<days>[\+\-]?\d+)\s*  # day part, like +5+
              (?<timesign>[\+\-])?
              (?<hours>\d+):(?<minutes>\d+)(?::(?<seconds>\d+(?:\.\d+)?))?
            )?  # time part, like -00:00:00
          $/x

          def type_cast_from_database(value)
            if value.kind_of? ::String
              match = POSTGRES_FORMAT.match(value) # Postgres format is the default, trying it first
              match = POSTGRES_VERBOSE_FORMAT.match(value)  unless match
              match = SQL_STANDARD_FORMAT.match(value)      unless match
              # It should be ISO8601 otherwise, let Duration handle it itself
              return ::ActiveSupport::Duration.parse(value) unless match
              # Construct ActiveSupport::Duration from parsed value
              parts = {}
              sign   = match.names.include?('signword') && match[:signword] == 'ago' ? -1 : 1 || 1
              ymsign = match.names.include?('yearmonthsign') && match[:yearmonthsign] == '-' ? -1 : 1 || 1
              parts[:years]  = sign * ymsign * match[:years].to_i   if match[:years]
              parts[:months] = sign * ymsign * match[:months].to_i  if match[:months]
              parts[:days]   = sign * match[:days].to_i             if match[:days]
              timesign = match.names.include?('timesign') && match[:timesign] == '-' ? -1 : 1 || 1
              parts[:hours] = sign * timesign * match[:hours].to_i      if match[:hours]
              parts[:minutes] = sign * timesign * match[:minutes].to_i  if match[:minutes]
              if match[:seconds]
                seconds_parse_method = /\d+\.\d+/ =~ match[:seconds] ? :to_f : :to_i
                parts[:seconds] = sign * timesign * match[:seconds].send(seconds_parse_method)
              end
              time = ::Time.now
              ::ActiveSupport::Duration.new(time.advance(parts) - time, parts)
            else
              super
            end
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
        end
      end
    end
  end
end
