# name: discourse-plugin-cleaner
# about: Safely identify and purge orphaned plugin, theme, and site setting data.
# version: 2.0.0
# authors: Can Bekcan
# url: https://github.com/canbekcan/discourse-plugin-cleaner

enabled_site_setting :plugin_cleaner_enabled

module ::DiscoursePluginCleaner
  PLUGIN_NAME = "discourse-plugin-cleaner".freeze
end

after_initialize do
  # Registers the route in the Discourse Admin Sidebar
  add_admin_route "plugin_cleaner.title", "plugin-cleaner"

  # Load the backend controller
  require_relative "app/controllers/admin/cleaner_controller"
end