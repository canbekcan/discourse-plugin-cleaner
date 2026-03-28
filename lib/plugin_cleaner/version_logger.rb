module PluginCleaner
  class VersionLogger
    def self.snapshot!
      PluginCleaner::VersionLog.snapshot_current_plugins!
    rescue => e
      Rails.logger.warn "[PluginCleaner] VersionLogger error: #{e.message}"
    end
  end
end
