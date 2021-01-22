require 'socket'
require 'net/ping'
class NetworkEnvironmentService
  class <<self
    def network_down?
      !Net::Ping::External.new('wiki.org').ping?
    end

    def primary_network_if
      Socket.getifaddrs.map(&:name).grep(Regexp.new(Rails.configuration.network_interface['primary'])).first
    end

    def monitor_network_if
      Socket.getifaddrs.map(&:name).grep(/wlx/).first
    end
  end
end
