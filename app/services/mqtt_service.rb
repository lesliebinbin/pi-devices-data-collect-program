require 'mqtt-rails'
class MqttService
  @device_id = File.read(Rails.configuration.mqtt[:device][:id_path]).chomp.to_i
  @family = File.read(Rails.configuration.mqtt[:device][:family]).chomp
  @device = File.read(Rails.configuration.mqtt[:device][:device]).chomp
  @location = File.read(Rails.configuration.mqtt[:device][:location]).chomp
  @area_id = File.read(Rails.configuration.mqtt[:device][:area_id_path]).chomp.to_i
  conn_opts = {
    persistent: true,
    reconnect_limit: -1,
    reconnect_delay: 1
  }
  @client = MqttRails::Client.new(conn_opts)
  pem_keys = %i[cert_file key_file ca_file]
  conn = Rails.configuration.mqtt[:connection].map do |k, v|
    if pem_keys.include? k
      [k, Rails.root.join('private', 'mqtt', v).to_s]
    else
      [k, v]
    end
  end.to_h
  @client.ssl = true
  @client.config_ssl_context(conn[:cert_file], conn[:key_file], conn[:ca_file])
  @client.connect('a1lj4k5or5rvza-ats.iot.ap-southeast-2.amazonaws.com', 8883)
  class <<self
    def publish(topic, content)
      puts topic
      puts content
      @client.publish(topic, content, false, 0)
    end

    def subscribe(*topics)
      @client.subscribe(*topics)
      @client
    end
    attr_reader :device_id, :family, :device, :location, :area_id
  end
end
