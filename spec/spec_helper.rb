# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__) + '/../lib')
$LOAD_PATH.unshift __dir__

if ENV['RCOV']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
  end
end

RSpec.configure do |config|
  config.pattern = '**{,/*/**}/*{_,.}spec.rb'
end
