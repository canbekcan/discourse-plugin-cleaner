module PluginCleaner
  class AdminController < ::Admin::AdminController
    requires_plugin PluginCleaner::PLUGIN_NAME

    # GET /admin/plugins/plugin-cleaner
    def index
      render json: { status: "ok", plugin: PluginCleaner::PLUGIN_NAME }
    end

    # GET /admin/plugins/plugin-cleaner/scan
    def scan
      result = PluginCleaner::Scanner.run
      render json: result
    end

    # DELETE /admin/plugins/plugin-cleaner/delete
    def delete
      items = params.require(:items)

      unless items.is_a?(Array) && items.any?
        return render json: { error: "No items provided" }, status: 422
      end

      results = PluginCleaner::Cleaner.delete!(items, performed_by: current_user)
      render json: { results: results }
    end

    # GET /admin/plugins/plugin-cleaner/versions
    def versions
      PluginCleaner::VersionLogger.snapshot!

      logs = PluginCleaner::VersionLog
        .order(created_at: :desc)
        .limit(500)
        .map do |log|
          {
            id:          log.id,
            plugin_name: log.plugin_name,
            version:     log.version,
            status:      log.status,
            notes:       log.notes,
            recorded_at: log.created_at.iso8601
          }
        end

      render json: { version_logs: logs }
    end
  end
end
