# frozen_string_literal: true

require "date"

module SFL
  module Core
    module Loaders
      class SillyTavernSource
        # Parses a send_date string such as "June 19, 2024 2:22pm" as US
        # Eastern wall-clock time and converts it to UTC.
        module SendDate
          # Shape of a send_date such as "June 19, 2024 2:22pm".
          PATTERN = /\A([A-Za-z]{3,9}) (\d{1,2}), (\d{4}) (\d{1,2}):(\d{2})(am|pm)\z/i

          # Returns a UTC Time, or nil when the text does not match the expected shape.
          def self.parse(raw)
            match = PATTERN.match(raw.to_s)
            return nil unless match

            month_name, day, year, hour12, minute, meridiem = match.captures
            month = month_number(month_name)
            day, year, hour12, minute = [day, year, hour12, minute].map(&:to_i)
            return nil unless valid_wall_time?(month, day, year, hour12, minute)

            eastern_to_utc(year, month, day, twenty_four_hour(hour12, meridiem), minute)
          end

          # Full or three-letter English month name to its number, or nil.
          def self.month_number(name)
            capitalized = name.capitalize
            Date::MONTHNAMES.index(capitalized) || Date::ABBR_MONTHNAMES.index(capitalized)
          end

          # Converts a 12-hour clock hour and am/pm marker to a 0-23 hour.
          def self.twenty_four_hour(hour12, meridiem) = (hour12 % 12) + (meridiem.casecmp?("pm") ? 12 : 0)

          # True when the parsed fields form a real 12-hour wall-clock time.
          def self.valid_wall_time?(month, day, year, hour12, minute)
            month && Date.valid_date?(year, month, day) && hour12.between?(1, 12) && minute < 60
          end

          # The single rule for US Eastern to UTC. EDT (UTC-4) runs from the
          # second Sunday of March at 2:00 local time to the first Sunday of
          # November at 2:00 local time; EST (UTC-5) otherwise.
          def self.eastern_to_utc(year, month, day, hour, minute)
            local = Date.new(year, month, day)
            wall = (hour * 60) + minute
            offset_hours = edt?(local, wall, year) ? 4 : 5
            Time.utc(year, month, day, hour, minute) + (offset_hours * 3600)
          end

          # True when local wall-clock time falls in EDT for the given year.
          def self.edt?(local, wall, year)
            dst_start = first_sunday_on_or_after(year, 3, 8) # second Sunday of March
            dst_end = first_sunday_on_or_after(year, 11, 1) # first Sunday of November
            if local == dst_start then wall >= 120
            elsif local == dst_end then wall < 120
            else local.between?(dst_start, dst_end)
            end
          end

          def self.first_sunday_on_or_after(year, month, day)
            date = Date.new(year, month, day)
            date + ((7 - date.wday) % 7)
          end

          private_class_method :month_number, :twenty_four_hour, :valid_wall_time?, :eastern_to_utc, :edt?, :first_sunday_on_or_after
        end
      end
    end
  end
end
