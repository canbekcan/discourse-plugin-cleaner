# name: discourse-plugin-cleaner
# about: Scans orphan plugin data and custom fields safely
# version: 0.2
# authors: canbekcan


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

  # Sadece yöneticilerin erişebileceği güvenli rota tanımlaması
  Discourse::Application.routes.append do
    scope "/admin", constraints: AdminConstraint.new do
      get "plugin-cleaner"      => "plugin_cleaner/admin#index",  as: :plugin_cleaner
      get "plugin-cleaner/scan" => "plugin_cleaner/admin#scan",   as: :plugin_cleaner_scan
    end
  end

  # Controller dosyasını mutlak yolla güvenli şekilde çağırıyoruz
  require_dependency File.expand_path("../app/controllers/plugin_cleaner/admin_controller.rb", __FILE__)
end