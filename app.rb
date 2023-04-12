#!/usr/bin/env ruby

require 'mechanize'
require 'icalendar'
require 'icalendar/tzinfo'

browser = Mechanize.new
# page = browser.get("https://montreal.ca/en/places/piscine-quintal")
page = browser.get("https://montreal.ca/lieux/piscine-quintal")
header_image = page.at('meta[property="og:image"]')['content']
author = page.at('meta[name="author"]')['content']
pool = page.at('meta[property="og:title"]')['content']

address = nil
page.search('div.list-item-icon-content').each do |item|
  if ['Address', 'Adresse'].include?(item.at('div.list-item-icon-label').text.strip)
    address = item.search('div')[1].
      children.
      map(&:text).
      map(&:strip).
      reject(&:empty?).
      join(', ')

    break
  end
end

message_bar = page.at('div.alert div.message-bar-container')
if message_bar
  notice_title = message_bar.at('div.message-bar-heading').text.strip
  notice_contents = message_bar.at('p').text.strip
end

contents = page.at('div.content-modules')

event_title = contents.at('h2').text.strip

season_from, season_to = contents.search('time').map do |time|
  DateTime.parse(time.attributes['datetime'].value)
end

weekdays_map = {
  "lundi" => "monday",
  "mardi" => "tuesday",
  "mercredi" => "wednesday",
  "jeudi" => "thursday",
  "vendredi" => "friday",
  "samedi" => "saturday",
  "dimanche" => "sunday",
}
weekdays_map.default_proc = Proc.new { |hash, key| key }

calendar = {}

contents.search('div.wrapper-body div.content-module-stacked').each do |section|
  section_header = section.at('h3').text.strip

  section.at('tbody').search('tr').each do |row|
    day, hours = row.search('td')
    day = DateTime.parse(day.text.strip.downcase.gsub(/^.*$/, weekdays_map))

    hour_start, hour_end = hours.search('span').map(&:text).map(&:strip).map do |hour|
      DateTime.parse(hour)
    end

    calendar[day.strftime('%w').to_i] ||= []
    calendar[day.strftime('%w').to_i].push({
      from: hour_start.strftime('%H:%M').split(':').map(&:to_i),
      to: hour_end.strftime('%H:%M').split(':').map(&:to_i),
      section: section_header,
    })
  end
end

cal = Icalendar::Calendar.new

tzid = "America/Montreal"
tz = TZInfo::Timezone.get(tzid)
timezone = tz.ical_timezone(season_from)
cal.add_timezone(timezone)

# Find the first date for each day of the week
calendar.sort.each do |day, periods|
  periods.sort_by { |period| [period[:from], period[:to]] }.each do |period|

    first_day = season_from + (day - season_from.wday) % 7

    event_start = DateTime.new(first_day.year, first_day.month, first_day.day, period[:from][0], period[:from][1], 0)
    event_end = DateTime.new(first_day.year, first_day.month, first_day.day, period[:to][0], period[:to][1], 0)

    cal.event do |e|
      # e.uid         = 'blah'
      e.dtstart     = Icalendar::Values::DateTime.new(event_start, 'tzid' => tzid)
      e.dtend       = Icalendar::Values::DateTime.new(event_end, 'tzid' => tzid)
      e.summary     = "#{event_title} #{period[:section].downcase}"

      if notice_title
        e.summary = "#{notice_title} - #{e.summary}"
        e.description = "#{notice_title} - #{notice_contents}"
        e.color = "#ffb833"
      else
        e.color = "#00a0e9"
      end

      # e.ip_class    = "PRIVATE"
      e.location    = "#{pool}, #{address}"
      e.url         = "https://montreal.ca/lieux/piscine-quintal"
      e.created     = DateTime.now
      e.last_modified = DateTime.now
      e.organizer   = author
      e.rrule       = "FREQ=WEEKLY;UNTIL=#{season_to.strftime('%Y%m%d')}"
      e.image       = header_image
    end

  end
end

cal.publish
puts cal.to_ical
