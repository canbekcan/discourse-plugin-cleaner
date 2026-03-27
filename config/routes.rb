Discourse::Application.routes.append do
  get "/admin/plugin-cleaner" => "plugin_cleaner/admin#index"
  get "/admin/plugin-cleaner/scan" => "plugin_cleaner/admin#scan"
end