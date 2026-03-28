class CreatePluginCleanerVersionLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :plugin_cleaner_version_logs do |t|
      t.string  :plugin_name,  null: false
      t.string  :version,      null: false
      t.string  :status,       null: false, default: "active"  # active | removed
      t.text    :notes
      t.timestamps
    end

    add_index :plugin_cleaner_version_logs, :plugin_name
    add_index :plugin_cleaner_version_logs, :status
  end
end
