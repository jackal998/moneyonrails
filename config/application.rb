require_relative "boot"

# Check out what rails/all.rb is currently expanded to:
#  https://github.com/rails/rails/blob/master/railties/lib/rails/all.rb

# Replace `require 'rails/all'` with just the libs that you want and
# exclude the rest

require "active_record/railtie"
# require 'active_storage/engine'
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
require "action_cable/engine"
# require 'action_mailbox/engine'
# require 'action_text/engine'
require "rails/test_unit/railtie"
require "sprockets/railtie"

# the rest of your initialization follows here ...

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Moneyonrails
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.

    config.time_zone = "Taipei"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
