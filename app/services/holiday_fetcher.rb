class HolidayFetcher
  API_URL = "https://holidays-jp.github.io/api/v1/%d/date.json"

  def self.fetch(year)
    uri = URI(API_URL % year)
    response = Net::HTTP.get_response(uri)
    return {} unless response.is_a?(Net::HTTPSuccess)
    JSON.parse(response.body).transform_keys { |k| Date.parse(k) }
  rescue StandardError
    {}
  end
end
