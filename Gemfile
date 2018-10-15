source 'https://rubygems.org'

gemspec

group :test do
  gem 'i18n', require: false
  platform :mri do
    gem 'simplecov', require: false
  end
end

group :tools do
  gem 'pry', platform: :jruby
  gem 'pry-byebug', platform: :mri

  unless ENV['TRAVIS']
    gem 'mutant', git: 'https://github.com/mbj/mutant'
    gem 'mutant-rspec', git: 'https://github.com/mbj/mutant'
  end
end
