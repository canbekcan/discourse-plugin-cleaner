# name: discourse-plugin-cleaner
# about: Scans orphan plugin data and custom fields safely
# version: 0.1
# authors: canbekcan

enabled_site_setting :plugin_cleaner_enabled

# Require lib files OUTSIDE after_initialize so they load correctly in all environments
require_relative "lib/plugin_cleaner/scanner"
require_relative "lib/plugin_cleaner/report"

after_initialize do
  module ::PluginCleaner
    PLUGIN_NAME = "plugin-cleaner"

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace PluginCleaner
    end
  end

  # Route must reference the full controller name with namespace
  Discourse::Application.routes.append do
    scope "/admin", constraints: AdminConstraint.new do
      get "plugin-cleaner"      => "plugin_cleaner/admin#index",  as: :plugin_cleaner
      get "plugin-cleaner/scan" => "plugin_cleaner/admin#scan",   as: :plugin_cleaner_scan
    end
  end

  # Controller must be defined AFTER the module and INSIDE after_initialize
  # but referenced correctly via the route above
  require_dependency "app/controllers/plugin_cleaner/admin_controller"
end