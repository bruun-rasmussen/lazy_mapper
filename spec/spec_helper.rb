# frozen_string_literal: true

if ENV['RCOV']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
  end
end

RSpec.configure do |config|
  config.pattern = '**{,/*/**}/*{_,.}spec.rb'
end
