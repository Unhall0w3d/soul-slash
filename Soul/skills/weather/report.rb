#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "time"
require "uri"

US_STATES = {
  "AL" => "Alabama", "AK" => "Alaska", "AZ" => "Arizona", "AR" => "Arkansas",
  "CA" => "California", "CO" => "Colorado", "CT" => "Connecticut", "DE" => "Delaware",
  "FL" => "Florida", "GA" => "Georgia", "HI" => "Hawaii", "ID" => "Idaho",
  "IL" => "Illinois", "IN" => "Indiana", "IA" => "Iowa", "KS" => "Kansas",
  "KY" => "Kentucky", "LA" => "Louisiana", "ME" => "Maine", "MD" => "Maryland",
  "MA" => "Massachusetts", "MI" => "Michigan", "MN" => "Minnesota", "MS" => "Mississippi",
  "MO" => "Missouri", "MT" => "Montana", "NE" => "Nebraska", "NV" => "Nevada",
  "NH" => "New Hampshire", "NJ" => "New Jersey", "NM" => "New Mexico", "NY" => "New York",
  "NC" => "North Carolina", "ND" => "North Dakota", "OH" => "Ohio", "OK" => "Oklahoma",
  "OR" => "Oregon", "PA" => "Pennsylvania", "RI" => "Rhode Island", "SC" => "South Carolina",
  "SD" => "South Dakota", "TN" => "Tennessee", "TX" => "Texas", "UT" => "Utah",
  "VT" => "Vermont", "VA" => "Virginia", "WA" => "Washington", "WV" => "West Virginia",
  "WI" => "Wisconsin", "WY" => "Wyoming", "DC" => "District of Columbia"
}.freeze

COUNTRY_ALIASES = {
  "US" => ["US", "USA", "UNITED STATES", "UNITED STATES OF AMERICA"],
  "GB" => ["GB", "UK", "U.K.", "UNITED KINGDOM", "GREAT BRITAIN", "ENGLAND", "SCOTLAND", "WALES", "NORTHERN IRELAND"],
  "CA" => ["CA", "CANADA"],
  "FR" => ["FR", "FRANCE"],
  "DE" => ["DE", "GERMANY", "DEUTSCHLAND"],
  "IT" => ["IT", "ITALY", "ITALIA"],
  "ES" => ["ES", "SPAIN", "ESPAÑA"],
  "IE" => ["IE", "IRELAND"],
  "NL" => ["NL", "NETHERLANDS", "THE NETHERLANDS", "HOLLAND"],
  "BE" => ["BE", "BELGIUM"],
  "CH" => ["CH", "SWITZERLAND"],
  "AT" => ["AT", "AUSTRIA"],
  "AU" => ["AU", "AUSTRALIA"],
  "NZ" => ["NZ", "NEW ZEALAND"],
  "JP" => ["JP", "JAPAN"],
  "KR" => ["KR", "SOUTH KOREA", "KOREA"],
  "MX" => ["MX", "MEXICO"],
  "BR" => ["BR", "BRAZIL"],
  "IN" => ["IN", "INDIA"]
}.freeze

COUNTRY_LOOKUP = COUNTRY_ALIASES.each_with_object({}) do |(code, aliases), memo|
  aliases.each { |name| memo[name.upcase] = code }
end.freeze

options = {
  location: ENV.fetch("SOUL_WEATHER_LOCATION", nil),
  units: ENV.fetch("SOUL_WEATHER_UNITS", "fahrenheit"),
  detailed: false,
  forecast_days: 3
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: report.rb --location LOCATION [--detailed]"
  opts.on("--location LOCATION", "Location name, e.g. 'Syracuse, NY' or 'London, UK'.") { |value| options[:location] = value }
  opts.on("--detailed", "Include a 3-day outlook and notable forecast signals.") { options[:detailed] = true }
  opts.on("--forecast-days N", Integer, "Forecast days for detailed output. Defaults to 3.") { |value| options[:forecast_days] = [[value, 1].max, 7].min }
  opts.on("--units UNITS", "fahrenheit or celsius. Defaults to fahrenheit.") { |value| options[:units] = value }
end

begin
  parser.parse!(ARGV)
rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
  puts JSON.pretty_generate({
    skill: "weather.report",
    status: "error",
    error: "#{e.class}: #{e.message}",
    usage: parser.to_s,
    verification: { read_only: true, network_only: true, wrote_files: false }
  })
  exit 2
end

def http_json(url)
  uri = URI(url)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 20) { |http| http.get(uri.request_uri) }
  { ok: res.is_a?(Net::HTTPSuccess), code: res.code.to_i, body: JSON.parse(res.body.to_s), url: url }
rescue StandardError => e
  { ok: false, code: nil, body: nil, url: url, error: "#{e.class}: #{e.message}" }
end

def weather_description(code)
  {
    0 => "Clear sky", 1 => "Mainly clear", 2 => "Partly cloudy", 3 => "Overcast",
    45 => "Fog", 48 => "Depositing rime fog",
    51 => "Light drizzle", 53 => "Moderate drizzle", 55 => "Dense drizzle",
    56 => "Light freezing drizzle", 57 => "Dense freezing drizzle",
    61 => "Slight rain", 63 => "Moderate rain", 65 => "Heavy rain",
    66 => "Light freezing rain", 67 => "Heavy freezing rain",
    71 => "Slight snow", 73 => "Moderate snow", 75 => "Heavy snow", 77 => "Snow grains",
    80 => "Slight rain showers", 81 => "Moderate rain showers", 82 => "Violent rain showers",
    85 => "Slight snow showers", 86 => "Heavy snow showers",
    95 => "Thunderstorm", 96 => "Thunderstorm with slight hail", 99 => "Thunderstorm with heavy hail"
  }.fetch(code.to_i, "Unknown weather code #{code}")
end

def us_aqi_category(value)
  return "Unavailable" if value.nil?

  case value.to_f
  when 0..50 then "Good"
  when 51..100 then "Moderate"
  when 101..150 then "Unhealthy for Sensitive Groups"
  when 151..200 then "Unhealthy"
  when 201..300 then "Very Unhealthy"
  else "Hazardous"
  end
end

def nearest_hourly_value(hourly, key)
  times = hourly["time"] || []
  values = hourly[key] || []
  return nil if times.empty? || values.empty?

  now = Time.now
  pairs = times.each_with_index.map do |stamp, index|
    parsed = Time.parse(stamp) rescue nil
    parsed ? [parsed, values[index]] : nil
  end.compact

  pairs.min_by { |time, _value| (time - now).abs }&.last
end

def format_temp(value, unit)
  return "unavailable" if value.nil?

  suffix = unit == "celsius" ? "°C" : "°F"
  "#{value.round}#{suffix}"
end

def country_code_for(value)
  cleaned = value.to_s.strip.upcase
  return nil if cleaned.empty?

  COUNTRY_LOOKUP[cleaned] || (cleaned.match?(/\A[A-Z]{2}\z/) ? cleaned : nil)
end

def parse_location_hint(location)
  raw = location.to_s.strip
  hint = {
    original: raw,
    city: raw,
    region_raw: nil,
    region_name: nil,
    country_code: nil
  }

  parts = raw.split(",").map(&:strip).reject(&:empty?)
  return hint if parts.length < 2

  city = parts.first
  region = parts[1]
  region_up = region.to_s.upcase

  hint[:city] = city unless city.empty?
  hint[:region_raw] = region unless region.empty?

  if US_STATES.key?(region_up)
    hint[:region_name] = US_STATES[region_up]
    hint[:country_code] = "US"
  elsif US_STATES.values.any? { |name| name.casecmp?(region) }
    hint[:region_name] = region
    hint[:country_code] = "US"
  else
    hint[:country_code] = country_code_for(region)
  end

  hint
end

def geocoding_attempts(location)
  hint = parse_location_hint(location)
  candidates = []
  original = hint[:original]
  city = hint[:city]
  country = hint[:country_code]

  candidates << { name: original, country_code: country, reason: "original_with_country_hint" } if country
  candidates << { name: city, country_code: country, reason: "city_with_country_hint" } if country && city != original
  candidates << { name: city, country_code: nil, reason: "city_only" } if city && !city.empty?
  candidates << { name: original, country_code: nil, reason: "original" } if original && !original.empty?
  candidates.uniq { |item| [item[:name], item[:country_code]] }
end

def score_geocoding_result(place, hint)
  score = 0
  original = hint[:original].to_s.downcase
  city = hint[:city].to_s.downcase
  region_name = hint[:region_name].to_s.downcase
  country_code = hint[:country_code].to_s.upcase

  name = place["name"].to_s.downcase
  admin1 = place["admin1"].to_s.downcase
  country = place["country_code"].to_s.upcase
  population = place["population"].to_i

  score += 100 if !city.empty? && name == city
  score += 50 if !city.empty? && name.include?(city)
  score += 75 if !region_name.empty? && admin1 == region_name
  score += 25 if !region_name.empty? && admin1.include?(region_name)
  score += 40 if !country_code.empty? && country == country_code
  score += 15 if original.include?(name)
  score += [population / 100_000, 30].min if population.positive?
  score
end

def resolve_location(location)
  hint = parse_location_hint(location)
  attempts = []
  all_results = []

  geocoding_attempts(location).each do |attempt|
    params = { name: attempt[:name], count: 10, language: "en", format: "json" }
    params[:countryCode] = attempt[:country_code] if attempt[:country_code]

    url = "https://geocoding-api.open-meteo.com/v1/search?#{URI.encode_www_form(params)}"
    response = http_json(url)

    attempts << {
      reason: attempt[:reason],
      name: attempt[:name],
      country_code: attempt[:country_code],
      ok: response[:ok],
      code: response[:code],
      result_count: response.dig(:body, "results").is_a?(Array) ? response.dig(:body, "results").length : 0,
      error: response[:error]
    }

    next unless response[:ok]
    Array(response.dig(:body, "results")).each { |place| all_results << place }
  end

  unique_results = all_results.uniq { |place| place["id"] || [place["name"], place["latitude"], place["longitude"]] }
  best = unique_results.max_by { |place| score_geocoding_result(place, hint) }

  { ok: !best.nil?, place: best, attempts: attempts, hint: hint, result_count: unique_results.length }
end

def notable_forecast_events(weather_daily, air_hourly)
  daily = weather_daily || {}
  events = []
  times = daily["time"] || []
  codes = daily["weather_code"] || []
  precip_probs = daily["precipitation_probability_max"] || []
  precip_sums = daily["precipitation_sum"] || []
  wind_max = daily["wind_speed_10m_max"] || []
  highs = daily["temperature_2m_max"] || []
  lows = daily["temperature_2m_min"] || []

  times.each_with_index do |day, index|
    code = codes[index]
    desc = weather_description(code)
    precip_prob = precip_probs[index].to_f if precip_probs[index]
    precip_sum = precip_sums[index].to_f if precip_sums[index]
    wind = wind_max[index].to_f if wind_max[index]
    high = highs[index].to_f if highs[index]
    low = lows[index].to_f if lows[index]

    if code.to_i >= 95
      events << "#{day}: thunderstorm signal in the forecast."
    elsif code.to_i.between?(71, 77) || code.to_i.between?(85, 86)
      events << "#{day}: snow or snow showers possible."
    elsif code.to_i.between?(61, 82) || (precip_prob && precip_prob >= 60) || (precip_sum && precip_sum >= 0.25)
      events << "#{day}: #{desc.downcase}; precipitation looks notable."
    end

    events << "#{day}: wind may be noticeable, with gusty/strong conditions possible." if wind && wind >= 25
    events << "#{day}: high temperature is notably hot." if high && high >= 90
    events << "#{day}: low temperature is below freezing." if low && low <= 32
  end

  aqi_values = Array(air_hourly&.fetch("us_aqi", []))
  max_aqi = aqi_values.compact.map(&:to_f).max
  if max_aqi && max_aqi >= 101
    events << "Air quality may become notable during the outlook period; forecast US AQI reaches #{max_aqi.round} (#{us_aqi_category(max_aqi)})."
  elsif max_aqi && max_aqi >= 51
    events << "Air quality may be moderate at times during the outlook period; forecast US AQI reaches #{max_aqi.round}."
  end

  events.uniq
end

def forecast_rows(weather_daily)
  daily = weather_daily || {}
  times = daily["time"] || []
  codes = daily["weather_code"] || []
  highs = daily["temperature_2m_max"] || []
  lows = daily["temperature_2m_min"] || []
  precip_probs = daily["precipitation_probability_max"] || []
  precip_sums = daily["precipitation_sum"] || []
  winds = daily["wind_speed_10m_max"] || []

  times.each_with_index.map do |day, index|
    {
      date: day,
      condition: weather_description(codes[index]),
      high: highs[index],
      low: lows[index],
      precipitation_probability_percent: precip_probs[index],
      precipitation_sum: precip_sums[index],
      max_wind_speed: winds[index]
    }
  end
end

location = options[:location].to_s.strip

if location.empty?
  puts JSON.pretty_generate({
    skill: "weather.report",
    generated_at: Time.now.iso8601,
    status: "needs_input",
    outcome: "location_required",
    recommendation: "Please provide a location, for example: ruby bin/soul do \"what is the weather in Syracuse, NY\". You can also set SOUL_WEATHER_LOCATION in .env.",
    verification: { read_only: true, network_only: true, wrote_files: false, location_present: false, complete: false }
  })
  exit 1
end

units = options[:units].to_s.downcase == "celsius" ? "celsius" : "fahrenheit"
temperature_unit = units == "celsius" ? "celsius" : "fahrenheit"
wind_unit = units == "celsius" ? "kmh" : "mph"
precip_unit = units == "celsius" ? "mm" : "inch"
now = Time.now

resolved = resolve_location(location)

unless resolved[:ok]
  puts JSON.pretty_generate({
    skill: "weather.report",
    generated_at: now.iso8601,
    status: "error",
    outcome: "geocoding_failed",
    location_query: location,
    parsed_location_hint: resolved[:hint],
    geocoding_attempts: resolved[:attempts],
    error: "No matching location found after retrying normalized query variants.",
    verification: { read_only: true, network_only: true, wrote_files: false, geocoding_ok: false, complete: false }
  })
  exit 1
end

place = resolved[:place]
lat = place["latitude"]
lon = place["longitude"]

weather_params = {
  latitude: lat,
  longitude: lon,
  current: "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m",
  daily: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max",
  forecast_days: options[:forecast_days],
  timezone: "auto",
  temperature_unit: temperature_unit,
  wind_speed_unit: wind_unit,
  precipitation_unit: precip_unit
}
weather_url = "https://api.open-meteo.com/v1/forecast?#{URI.encode_www_form(weather_params)}"
weather = http_json(weather_url)

air_params = { latitude: lat, longitude: lon, hourly: "us_aqi,pm2_5,pm10", forecast_days: options[:forecast_days], timezone: "auto" }
air_url = "https://air-quality-api.open-meteo.com/v1/air-quality?#{URI.encode_www_form(air_params)}"
air = http_json(air_url)

unless weather[:ok]
  puts JSON.pretty_generate({
    skill: "weather.report",
    generated_at: now.iso8601,
    status: "error",
    outcome: "weather_fetch_failed",
    location_query: location,
    resolved_location: place,
    geocoding_attempts: resolved[:attempts],
    error: weather[:error] || "Weather API returned HTTP #{weather[:code]}",
    verification: { read_only: true, network_only: true, wrote_files: false, geocoding_ok: true, weather_fetch_ok: false, complete: false }
  })
  exit 1
end

current = weather.dig(:body, "current") || {}
air_hourly = air[:ok] ? air.dig(:body, "hourly") : {}
aqi = nearest_hourly_value(air_hourly || {}, "us_aqi")
pm25 = nearest_hourly_value(air_hourly || {}, "pm2_5")
pm10 = nearest_hourly_value(air_hourly || {}, "pm10")

resolved_name = [place["name"], place["admin1"], place["country_code"]].compact.reject(&:empty?).join(", ")

brief = {
  location: resolved_name,
  observed_at: current["time"],
  temperature: current["temperature_2m"],
  temperature_unit: units == "celsius" ? "celsius" : "fahrenheit",
  condition: weather_description(current["weather_code"]),
  humidity_percent: current["relative_humidity_2m"],
  wind_speed: current["wind_speed_10m"],
  air_quality: {
    us_aqi: aqi,
    category: us_aqi_category(aqi),
    pm2_5: pm25,
    pm10: pm10
  }
}

daily = weather.dig(:body, "daily") || {}
outlook = forecast_rows(daily)
events = notable_forecast_events(daily, air_hourly)

summary_lines = []
summary_lines << "Weather for #{resolved_name}: #{brief[:condition]}, #{format_temp(brief[:temperature], units)}."
summary_lines << "Humidity is #{brief[:humidity_percent]}%." if brief[:humidity_percent]
if aqi
  summary_lines << "Air quality is #{aqi.round} US AQI (#{us_aqi_category(aqi)})."
else
  summary_lines << "Air quality is unavailable from the provider right now."
end

result = {
  skill: "weather.report",
  generated_at: now.iso8601,
  status: air[:ok] ? "ok" : "warning",
  outcome: "complete",
  mode: options[:detailed] ? "detailed" : "brief",
  location_query: location,
  parsed_location_hint: resolved[:hint],
  geocoding_attempts: resolved[:attempts],
  resolved_location: {
    name: resolved_name,
    latitude: lat,
    longitude: lon,
    timezone: weather.dig(:body, "timezone"),
    provider_id: place["id"],
    population: place["population"]
  },
  current: brief,
  summary: summary_lines.join(" "),
  detailed_report: options[:detailed] ? {
    outlook_days: outlook,
    notable_forecast_signals: events.empty? ? ["No notable forecast signals detected in the 3-day outlook."] : events
  } : nil,
  recommendation: options[:detailed] ? "Detailed weather report complete." : "Brief weather report complete. Ask for the detailed report to include a 3-day outlook and notable forecast signals.",
  verification: {
    read_only: true,
    network_only: true,
    wrote_files: false,
    geocoding_ok: resolved[:ok],
    geocoding_result_count: resolved[:result_count],
    weather_fetch_ok: weather[:ok],
    air_quality_fetch_ok: air[:ok],
    complete: true,
    final_state: options[:detailed] ? "complete" : "brief_complete_detail_available"
  },
  warnings: []
}

result[:warnings] << "Air quality fetch failed: #{air[:error] || "HTTP #{air[:code]}"}" unless air[:ok]

puts JSON.pretty_generate(result)
