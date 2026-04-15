Discourse::Application.routes.append do
  namespace :admin, constraints: AdminConstraint.new do
    namespace :plugins do
      get "plugin-cleaner/scan" => "cleaner#scan"
      delete "plugin-cleaner/purge" => "cleaner#purge"
    end
  end
end