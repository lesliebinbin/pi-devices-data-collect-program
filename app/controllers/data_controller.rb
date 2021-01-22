require 'rest-client'
require 'json'
class DataController < ApplicationController
  def accept
    params.permit!
    ScanningService.submit_wifi_sniff_result(params[:datum]) do |result|
      MqttService.publish Rails.configuration.mqtt[:topics][:wififindif], result
    end

    # RestClient.post('http://13.210.204.62:8003/data', request.raw_post, { content_type: :json, accept: :json })
  ensure
    render json: { message: 'inserted data', success: true }
  end

  def tracker
    params.permit!
    mqtt, find3 = DataProcessService.process(request.raw_post).values_at(:mqtt, :find3)
    Rails.application.executor.wrap do
      # ScanningService.accept_wifi_sniff_find3(find3)
      # ScanningService.accept_wifi_sniff_mqtt(mqtt)
    end
  ensure
    render json: { message: 'inserted data', success: true }
  end

  def dmesg
    # hello, here
    # here again
    params.permit!
    ScanningService.submit_kernel_info_mqtt(request.raw_post)
    render json: { message: 'inserted data', success: true }
  end

  def update_pi_info
    params.permit!
    MqttService.publish(Rails.configuration.mqtt[:topics][:pi], { type: 'request', mac: ScanningService.mac_addr }.to_json)
    render json: { message: 'updated data', success: true }
  end

  def ubertooth
    params.permit!
    ScanningService.parse_ubertooth_each_line(JSON.parse(request.raw_post)['line'])
  ensure
    render json: { message: 'updated data', success: true }
  end
end
