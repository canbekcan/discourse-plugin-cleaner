# name: discourse-plugin-cleaner
# about: Scans orphan plugin data and custom fields safely
# version: 0.3
# authors: canbekcan

enabled_site_setting :discourse_plugin_cleaner_enabled

# Sol menü bağlantısını ekleyen standart Discourse metodu
add_admin_route "discourse_plugin_cleaner.title", "discourse-plugin-cleaner"

require_relative "lib/discourse_plugin_cleaner/scanner"
require_relative "lib/discourse_plugin_cleaner/report"

after_initialize do
  module ::DiscoursePluginCleaner
    PLUGIN_NAME = "discourse-plugin-cleaner"

    class Engine < ::Rails::Engine
      engine_name PLUGIN_NAME
      isolate_namespace DiscoursePluginCleaner
    end
  end

  Discourse::Application.routes.append do
    # Sol menüye tıklandığında Ember arayüzünü yükleyen rota
    get "/admin/plugins/discourse-plugin-cleaner" => "admin/plugins#index", constraints: AdminConstraint.new
    
    # JSON verisini çeken tarama rotası
    scope "/admin/discourse-plugin-cleaner", constraints: AdminConstraint.new do
      get "scan" => "discourse_plugin_cleaner/admin#scan"
    end
  end

  require_dependency File.expand_path("../app/controllers/discourse_plugin_cleaner/admin_controller.rb", __FILE__)
end