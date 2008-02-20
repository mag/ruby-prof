# These 3 lines MUST be included at the top of every profile test
ENV["RAILS_ENV"] = "profile"
require File.expand_path(File.dirname(__FILE__) + "/../../config/environment")
require "profile_test"

class ExampleTest < ActionController::ProfileTest
  def test_cart_controller
    result = profile(:get, 'cart/get')
    report(result, :printer => RubyProf::FlatPrinter)
    report(result, :printer => RubyProf::GraphHtmlPrinter)
  end
end   
