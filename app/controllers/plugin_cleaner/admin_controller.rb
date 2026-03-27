module PluginCleaner
  # Sadece adminlerin erişebilmesi için ::Admin::AdminController'dan miras alıyoruz
  class AdminController < ::Admin::AdminController
    requires_plugin PluginCleaner::PLUGIN_NAME

    def index
      render json: { status: "Plugin Cleaner is active and ready." }
    end

    def scan
      # Sizin yazdığınız o harika Scanner ve Report modüllerini burada tetikliyoruz
      scan_result = PluginCleaner::Scanner.run
      report = PluginCleaner::Report.generate(scan_result)
      
      render json: report
    end
  end
end