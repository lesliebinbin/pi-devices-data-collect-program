require 'json'
module Space
  class SensorData
    attr_accessor :t, :f, :d, :l, :s, :gps
    def initialize(opts = {})
      opts.each do |k, v|
        send("#{k}=", v)
      end
    end

    def to_json(*_args)
      self.instance_variables.map do |variable|
        [variable[1..-1], instance_variable_get(variable)]
      end.to_h.to_json
    end
    class <<self
      def from_json(json_str)
        SensorData.new(JSON.parse(json_str))
      end
    end
  end
end
