module PluginCleaner
  class VersionLog < ActiveRecord::Base
    self.table_name = "plugin_cleaner_version_logs"

    validates :plugin_name, presence: true
    validates :version,     presence: true
    validates :status,      inclusion: { in: %w[active removed] }

    scope :active,   -> { where(status: "active") }
    scope :removed,  -> { where(status: "removed") }
    scope :recent,   -> { order(created_at: :desc).limit(200) }

    def self.snapshot_current_plugins!
      active_plugins = Discourse.plugins.map do |plugin|
        { name: plugin.name, version: plugin.metadata.version.to_s }
      end

      active_plugins.each do |p|
        existing = find_by(plugin_name: p[:name], status: "active")
        next if existing && existing.version == p[:version]

        # Mark old active record as removed if version changed
        existing&.update!(status: "removed", notes: "Version changed to #{p[:version]}")

        create!(
          plugin_name: p[:name],
          version:     p[:version],
          status:      "active",
          notes:       "Recorded at boot"
        )
      end

      # Mark plugins no longer present as removed
      active_names = active_plugins.map { |p| p[:name] }
      where(status: "active")
        .where.not(plugin_name: active_names)
        .update_all(status: "removed", notes: "Plugin no longer present")
    end
  end
end
