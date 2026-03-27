module PluginCleaner
  class AdminController < ::Admin::AdminController
    requires_plugin PluginCleaner::PLUGIN_NAME
    before_action :ensure_plugin_active

    def index
      render json: { status: "Plugin Cleaner is active and ready." }
    end

    def scan
      scan_result = PluginCleaner::Scanner.run
      report = PluginCleaner::Report.generate(scan_result)
      render json: report
    end

    private

    def ensure_plugin_active
      raise Discourse::NotFound unless SiteSetting.plugin_cleaner_enabled
    end
  end
end