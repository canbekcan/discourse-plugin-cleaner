module PluginCleaner
  class AdminController < ::Admin::AdminController
    requires_plugin PluginCleaner::PLUGIN_NAME

    def index
      render json: { status: "ok", message: "Plugin Cleaner Active" }
    end

    def scan
      result = PluginCleaner::Scanner.run
      report = PluginCleaner::Report.generate(result)
      render json: report
    end
  end
end
