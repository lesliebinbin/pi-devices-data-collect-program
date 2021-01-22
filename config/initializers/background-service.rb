require 'rufus-scheduler'
require 'json'
require 'date'
require 'chronic'
require 'rest-client'
require 'mqtt'

unless defined?(Rails::Console)
  scheduler = Rufus::Scheduler.new
  publish = MqttService.public_method(:publish)
  submit_useful_macs = ScanningService.public_method(:submit_useful_macs)
  submit_ubertooth_result = ScanningService.public_method(:submit_ubertooth_result)

  scheduler.every '20s' do
    submit_useful_macs.call do |result|
      publish[Rails.configuration.mqtt[:topics][:ubertooth_survey_result], result]
    end

  end

  scheduler.every Rails.configuration.background_scheduler[:ubertooth][:submit] do
    submit_ubertooth_result.call do |result|
      publish[Rails.configuration.mqtt[:topics][:utcl], result]
    end
  end

  # scheduler.every Rails.configuration.background_scheduler[:wifi][:lan] do
  #   ScanningService.lan_scan do |result|
  #     MqttService.publish Rails.configuration.mqtt[:topics][:wifilanscan], result
  #   end
  # end

  scheduler.in '1s' do
    client = MqttService.subscribe(Rails.configuration.mqtt[:topics][:bluez_device_name],
                                   Rails.configuration.mqtt[:topics][:pi])
    client.on_message do |msg|
      topic = msg.topic
      message = JSON.parse(msg.payload, symbolize_names: true)
      if topic == Rails.configuration.mqtt[:bluez_device_name]
        if (message[:type] == 'request') && (message[:device_id] == MqttService.device_id)
          device_name = BluetoothDeviceService.device_name(message[:mac])
          MqttService.publish(Rails.configuration.mqtt[:topics][:bluez_device_name],
                              { type: 'response',
                                mac: message[:mac],
                                name: device_name,
                                pi_id: MqttService.device_id,
                                area_id: MqttService.area_id }.to_json)
        end
      elsif topic == Rails.configuration.mqtt[:topics][:pi]
        if message[:type] == 'response' && message[:mac] == ScanningService.mac_addr
          device_id, area_id = message.values_at(:pi_id, :area_id)
          MqttService.reset_the_pi(device_id, area_id)
          File.write(Rails.configuration.mqtt[:device][:id_path], device_id)
          File.write(Rails.configuration.mqtt[:device][:area_id_path], area_id)
        end

      else
        puts 'something else'
      end
    end
  end

  # scheduler.every '30s' do
  #   ScanningService.bluetooth_scan do |result|
  #     MqttService.publish Rails.configuration.mqtt[:topics][:bluez], result
  #   end
  # end
  scheduler.every '60s' do
    Dir.children(Rails.configuration.mqtt[:network_down_folder]).each do |file|
      abs_path = File.join(Rails.configuration.mqtt[:network_down_folder], file)
      topic, content = Marshal.load(File.read(abs_path)).values_at(:topic, :content)
      MqttService.publish(topic, content)
      FileUtils.rm_rf(abs_path)
    end
  end

  # scheduler.every '10s' do
  #   ScanningService.submit_wifi_sniff_find3 do |result|
  #     RestClient.post('http://13.210.204.62:8003/data', result, { content_type: :json, accept: :json })
  #   end
  # end

  scheduler.every '60s' do
    current_temp = `vcgencmd measure_temp`.chomp.match(/temp=(?<temp>\d+\.\d+)'C/)[:temp].to_f
    if current_temp > 72
      begin
        RestClient.post(Rails.configuration.web_hook[:url],
                        { text: "alert, the temperature of #{`hostname`} is now #{current_temp}" }.to_json,
                        { content_type: :json, accept: :json })
      ensure
        `sudo reboot` if current_temp >= 85
      end

    end
  end

end
