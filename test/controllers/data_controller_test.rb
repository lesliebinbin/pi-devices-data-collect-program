require 'test_helper'

class DataControllerTest < ActionDispatch::IntegrationTest
  test "should get accept" do
    get data_accept_url
    assert_response :success
  end

end
