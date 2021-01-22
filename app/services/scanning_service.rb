require 'hooray'
require 'macaddr'
require 'rest-client'
require 'json'
require 'date'
require 'resolv'
require 'English'
require 'space/sensor_data'
require 'concurrent'

class ScanningService
  @global_ubertooth_monitor = Monitor.new
  @global_wifi_sniff_mqtt_monitor = Monitor.new
  @global_wifi_sniff_find3_monitor = Monitor.new
  @ubertooth_result_array = Concurrent::Array.new
  @wifisniff_result_mqtt = Concurrent::Array.new
  @ubertooth_job_hash = { day: nil, night: nil }
  @useful_macs = Concurrent::Array.new
  @mac_addr = Mac.addr
  @sensor_data_wifi = Space::SensorData.new(f: MqttService.family,
                                            d: MqttService.device,
                                            gps: Concurrent::Hash.new,
                                            s: { wifi: Concurrent::Hash.new })
  class <<self
    attr_reader :mac_addr
    def no_ubertooth_jobs_currently_working?
      @ubertooth_job_hash.values_at(:day, :night).all?(&:nil?)
    end

    def accept_wifi_sniff_find3(item)
      k, v = item
      @sensor_data_wifi.s[:wifi][k] = v
    end

    def accept_wifi_sniff_mqtt(item)
      @wifisniff_result_mqtt << item
      if @wifisniff_result_mqtt.count == Rails.configuration.background_scheduler[:max_buffer_size]
        submit_wifi_sniff_mqtt do |result|
          MqttService.publish(Rails.configuration.mqtt[:topics][:wififindif], result)
        end

      end
    end

    def submit_kernel_info_mqtt(info)
      MqttService.publish(Rails.configuration.mqtt[:topics][:kernel_info],
                          { submit_time: Time.now.to_i,
                            content: info,
                            type: 'kernel_info',
                            mac: @mac_addr,
                            pi_id: MqttService.device_id,
                            area_id: MqttService.area_id }.to_json)
    end

    def submit_wifi_sniff_mqtt
      yield({ submit_time: Time.now.to_i,
              items: @wifisniff_result_mqtt,
              type: 'wifisniff',
              mac: @mac_addr,
              pi_id: MqttService.device_id,
              area_id: MqttService.area_id }.to_json)
      @wifisniff_result_mqtt.clear
    end

    def submit_wifi_sniff_find3
      @sensor_data_wifi.t = Time.now.to_i
      yield(@sensor_data_wifi.to_json)
      @sensor_data_wifi.s[:wifi].clear
    end

    def discover_classic_devices(error_rate = 0, &block)
      Open3.popen3("ubertooth-rx -z -e #{error_rate}", &block)
    rescue Errno::ESRCH => e
      RestClient.post(
        Rails.configuration.web_hook[:url],
        { text: "device: ubertooth, date_time: #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')} ,host:#{`hostname`}, mac: #{@mac_addr}, error: ubertooth device is not working, retry_in: 30s" }.to_json,
        { content_type: :json, accept: :json }
      )
      sleep 30
      retry
    rescue EOFError => e
      RestClient.post(
        Rails.configuration.web_hook[:url],
        { text: "device: ubertooth, date_time: #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')} ,host:#{`hostname`}, mac: #{@mac_addr}, error: ubertooth scanning tasks is interrupeted,#{e.message}, retry in 10 s" }.to_json,
        { content_type: :json, accept: :json }
      )
      sleep 10
      retry
    rescue StandardError => e
      # log to local
      RestClient.post(
        Rails.configuration.web_hook[:url],
        { text: "device: ubertooth, date_time: #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')} ,host:#{`hostname`}, mac: #{@mac_addr}, error: #{e.message}, retry_in: 20s" }.to_json,
        { content_type: :json, accept: :json }
      )
      # send notify to teams
      sleep 20
      retry
    end

    def discover_classic_devices_with_timeout(error_rate = 1, timeout = 60, &block)
      Open3.popen3("ubertooth-rx -z -e #{error_rate} -t #{timeout}", &block)
    rescue Errno::ESRCH => e
      RestClient.post(
        Rails.configuration.web_hook[:url],
        { text: "device: ubertooth, date_time: #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')} ,host:#{`hostname`}, mac: #{@mac_addr}, error: ubertooth device is not working, retry_in: 30s" }.to_json,
        { content_type: :json, accept: :json }
      )
      sleep 30
      retry
    rescue EOFError => e
      RestClient.post(
        Rails.configuration.web_hook[:url],
        { text: "device: ubertooth, date_time: #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')} ,host:#{`hostname`}, mac: #{@mac_addr}, error: ubertooth scanning tasks is interrupeted, retry in 10 s, #{e.message}" }.to_json,
        { content_type: :json, accept: :json }
      )
      sleep 10
      retry
    rescue StandardError => e
      # log to local
      RestClient.post(
        Rails.configuration.web_hook[:url],
        { text: "device: ubertooth, date_time: #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')} ,host:#{`hostname`}, mac: #{@mac_addr}, error: #{e.message}, retry_in: 30s" }.to_json,
        { content_type: :json, accept: :json }
      )
      # send notify to teams
      sleep 30
      retry
    end

    def parse_ubertooth_each_line(line)
      case line
      when /systime=(?<systime>\d+) ch=( |\d)+ LAP=(?<lap>\w+{6}) err=-?\d+ clkn=-?\d+ clk_offset=-?\d+ s=(?<rssi>-?\d+) n=-?\d+ snr=(?<noise>-?\d+)/
        matcher = $LAST_MATCH_INFO
        lap, rssi, systime = matcher.values_at(:lap, :rssi, :systime)
        return  if lap == '9e8b33'

        @ubertooth_result_array << { systime: systime, lap: BluetoothDeviceService.convert_mac(lap), rssi: rssi.to_i }
        if @ubertooth_result_array.count == Rails.configuration.background_scheduler[:max_buffer_size]
          submit_ubertooth_result do |result|
            MqttService.publish Rails.configuration.mqtt[:topics][:utcl], result
          end
        end

      when /\?{2}:\?{2}:(?<mac>\h{2}:\h{2}:\h{2}:\h{2})/
        matcher = $LAST_MATCH_INFO
        @useful_macs << "00:00:#{matcher[:mac]}"
        if @useful_macs == Rails.configuration.background_scheduler[:max_buffer_size]
          submit_useful_macs do |result|
            MqttService.publish Rails.configuration.mqtt[:topics][:ubertooth_survey_result], result
          end
        end
      when /usb_claim_interface error/
        ErrorReportService.report_err({ text: "device: ubertooth, date_time: #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')} ,host:#{`hostname`}, mac: #{@mac_addr}, ubertooth conflict, error: #{line}" })
      when /could not open Ubertooth device/
        ErrorReportService.report_err({ text: "device: ubertooth, date_time: #{DateTime.now.strftime('%d/%m/%Y %H:%M:%S')} ,host:#{`hostname`}, mac: #{@mac_addr}, ubertooth device error: #{line}" })
      end
    end

    def submit_useful_macs
      return if @useful_macs.empty?

      yield({ submit_time: Time.now.to_i, items: @useful_macs, type: 'ubertoothsurvey', mac: @mac_addr,
              pi_id: MqttService.device_id, area_id: MqttService.area_id }.to_json)
      @useful_macs.clear
    end

    def resolve_name(ip)
      Resolv.getname(ip)
    rescue StandardError
      nil
    end

    def lan_scan
      read, write = IO.pipe
      pid = fork do
        read.close
        result = Hooray::Seek.new.nodes.map do |node|
          name = resolve_name(node.ip.to_s)
          { name: name, mac: node.mac, ip: node.ip.to_s }
        end
        result = result.reject do |item|
          item[:mac].nil?
        end
        result = 'Empty!' if result.empty?
        Marshal.dump(result, write)
        write.close
        exit!(0)
      end
      write.close
      result = read.read
      Process.wait(pid)
      result = Marshal.load(result)
      read.close
      result = [] if result == 'Empty!'
      if block_given?
        yield({ submit_time: Time.now.to_i, items: result, type: 'wifilanscan',
                mac: @mac_addr,
                pi_id: MqttService.device_id,
                area_id: MqttService.area_id }.to_json)
      end
    end

    def submit_wifi_sniff_result(data)
      return unless block_given?

      yield({ submit_time: data[:t],
              items: data[:s][:wifi].to_h.map { |k, v| { mac: k, rssi: v } },
              type: 'wififindif',
              mac: @mac_addr,
              pi_id: MqttService.device_id,
              area_id: MqttService.area_id,
              family: data[:f],
              device: data[:d] }.to_json)
    end

    def bluetooth_scan
      scan_results = BluetoothDeviceService.bluetooth_discovery_scan
      items = scan_results.lines.drop(1).map do |line|
        mac, device_name = line.chomp.split("\t").drop(1)
        { mac: mac, device_name: device_name }
      end
      return unless block_given?

      yield({ submit_time: Time.now.to_i,
              items: items,
              type: 'bluez_discovery',
              mac: @mac_addr,
              pi_id: MqttService.device_id,
              area_id: MqttService.area_id }.to_json)
    end

    def submit_ubertooth_result
      return unless block_given?

      yield({ submit_time: Time.now.to_i, items: @ubertooth_result_array, type: 'utcl',
              mac: @mac_addr, pi_id: MqttService.device_id, area_id: MqttService.area_id }.to_json)
      @ubertooth_result_array.clear
    end
  end
end
