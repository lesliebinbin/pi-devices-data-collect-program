require 'json'
class DataProcessService
  class << self
    def process(data)
      json_data = JSON.parse(data, symbolize_names: true)
      timestamp = Time.now.to_i
      mqtt = json_data.clone
      mqtt[:timestamp] = timestamp
      find3 = json_data.values_at(:mac, :rssi)
      { mqtt: mqtt, find3: find3 }
    end
  end
end
