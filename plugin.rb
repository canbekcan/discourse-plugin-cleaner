# name: discourse-plugin-cleaner
# about: Scans and cleans orphaned plugin data left in the database after plugins are removed
# version: 1.0.0
# authors: Can Bekcan
# url: https://github.com/canbekcan/discourse-plugin-cleaner
# meta_topic_id: ~

register_asset "stylesheets/admin/plugin-cleaner.scss", :admin

require_relative "lib/plugin_cleaner/scanner"
require_relative "lib/plugin_cleaner/cleaner"
require_relative "lib/plugin_cleaner/version_logger"

after_initialize do
  module ::PluginCleaner
    PLUGIN_NAME = "discourse-plugin-cleaner"

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace PluginCleaner
    end
  end

  # Routes
  Discourse::Application.routes.append do
    scope "/admin/plugins/plugin-cleaner", constraints: AdminConstraint.new do
      get    "/"            => "plugin_cleaner/admin#index"
      get    "/scan"        => "plugin_cleaner/admin#scan"
      delete "/delete"      => "plugin_cleaner/admin#delete"
      get    "/versions"    => "plugin_cleaner/admin#versions"
    end
  end

  # Register admin sidebar link
  add_admin_route "plugin_cleaner.title", "plugin-cleaner"

  require_dependency File.expand_path(
    "../app/controllers/plugin_cleaner/admin_controller.rb", __FILE__
  )
  require_dependency File.expand_path(
    "../app/models/plugin_cleaner/version_log.rb", __FILE__
  )
end
