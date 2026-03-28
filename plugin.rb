# name: discourse-plugin-cleaner
# about: Scans orphan plugin data and custom fields safely
# version: 0.3
# authors: canbekcan
# url: https://github.com/canbekcan/discourse-plugin-cleaner

enabled_site_setting :plugin_cleaner_enabled

require_relative "lib/plugin_cleaner/scanner"
require_relative "lib/plugin_cleaner/report"

after_initialize do
  module ::PluginCleaner
    PLUGIN_NAME = "discourse-plugin-cleaner"

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace PluginCleaner
    end
  end

  PluginCleaner::Engine.routes.draw do
    get "/scan" => "admin#scan"
  end

  Discourse::Application.routes.append do
    mount PluginCleaner::Engine, at: "/plugin-cleaner"
    get "/admin/plugins/plugin-cleaner" => "plugin_cleaner/admin#index",
        constraints: AdminConstraint.new
    get "/admin/plugins/plugin-cleaner/scan" => "plugin_cleaner/admin#scan",
        constraints: AdminConstraint.new
  end

  require_dependency File.expand_path(
    "../app/controllers/plugin_cleaner/admin_controller.rb", __FILE__
  )
end
