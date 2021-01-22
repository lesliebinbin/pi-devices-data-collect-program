require 'rest-client'
require 'json'
class ErrorReportService
  class <<self
    def report_err(content, url = Rails.configuration.web_hook[:url])
      RestClient.post(
        url,
        { text: "host: #{`hostname`} got the error: #{content}" }.to_json,
        { content_type: :json, accept: :json }
      )
    rescue StandardError
      Rails.logger.error content
    end
  end
end
