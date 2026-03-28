module DiscoursePluginCleaner
  class AdminController < ::Admin::AdminController
    requires_plugin DiscoursePluginCleaner::PLUGIN_NAME
    before_action :ensure_plugin_active

    def scan
      scan_result = DiscoursePluginCleaner::Scanner.run
      report = DiscoursePluginCleaner::Report.generate(scan_result)
      render json: report
    end

    private

    def ensure_plugin_active
      raise Discourse::NotFound unless SiteSetting.discourse_plugin_cleaner_enabled
    end
  end
end