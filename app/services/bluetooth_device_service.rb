require 'monitor'
class BluetoothDeviceService
  @global_monitor = Monitor.new
  class <<self
    def device_name(mac)
      @global_monitor.synchronize do
        `hcitool name #{mac}`.chomp unless mac =~ /00:00:00/
      end
    end

    def bluetooth_discovery_scan
      @global_monitor.synchronize do
        `hcitool scan`
      end
    end

    def convert_mac(hex_str, padding = false)
      # use an extra optional param in case in future it fucking needs this back
      valid_hex_digits = hex_str.upcase.scan(/(\h{2})/)
      if padding
        padding_hex_digits = 6 - valid_hex_digits.size
        (['00'] * padding_hex_digits + valid_hex_digits.flatten).join(':')
      else
        valid_hex_digits.flatten.join(':')
      end
    end
  end
end
