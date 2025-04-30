# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'pry-byebug'
require 'pry-stackexplorer'
require 'awesome_print'

if (ENV['COVERAGE'] || 0).to_i > 0
  require 'simplecov'
  SimpleCov.at_exit do
    # Workaround GC Bug: simplecov-html.rb:22:in `close': Bad file descriptor @ fptr_finalize
    GC.start
    SimpleCov.result.format!
  end
  SimpleCov.start do
    enable_coverage :branch
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.full_backtrace = true if ENV['TEST_BACKTRACE']
end

TEST_VERBOSE = ENV.fetch('TEST_VERBOSE', '0').to_i != 0
