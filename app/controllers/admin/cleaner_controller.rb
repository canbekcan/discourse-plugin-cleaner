class Admin::CleanerController < ::Admin::AdminController
  requires_plugin ::DiscoursePluginCleaner::PLUGIN_NAME

  def scan
    render json: {
      plugin_store: orphaned_plugin_store_rows,
      theme_settings: orphaned_theme_settings,
      site_settings: orphaned_site_settings
    }
  end

  def purge
    type = params.require(:data_type)
    items = params.require(:items)
    is_dry_run = params[:dry_run] == "true"

    deleted_count = 0

    unless is_dry_run
      case type
      when "plugin_store"
        deleted_count = PluginStoreRow.where(id: items).delete_all
      when "theme_settings"
        deleted_count = ThemeSetting.where(id: items).delete_all
      when "site_settings"
        deleted_count = DB.exec("DELETE FROM site_settings WHERE name IN (?)", items)
        SiteSetting.refresh!
      end

      # Clear global cache and synchronize Redis after destructive operations
      Rails.cache.clear
      MessageBus.publish("/plugin_cleaner/purged", { type: type })
    end

    StaffActionLogger.new(current_user).log_custom("purged_orphaned_data", { type: type, count: deleted_count, dry_run: is_dry_run })

    render json: { success: true, purged_count: deleted_count, dry_run: is_dry_run }
  end

  private

  def orphaned_plugin_store_rows
    active_plugins = Discourse.plugins.map(&:name)
    safe_core_namespaces = %w[core discourse poll discourse-local-dates]
    safe_list = active_plugins + safe_core_namespaces

    PluginStoreRow.where.not(plugin_name: safe_list)
                  .select(:id, :plugin_name, :key)
                  .limit(500)
                  .map { |r| { id: r.id, namespace: r.plugin_name, key: r.key } }
  end

  def orphaned_theme_settings
    ThemeSetting.where.not(theme_id: Theme.select(:id))
                .select(:id, :theme_id, :name)
                .limit(500)
                .map { |r| { id: r.id, theme_id: r.theme_id, name: r.name } }
  end

  def orphaned_site_settings
    valid_settings = SiteSetting.all_settings.map { |s| s[:setting].to_s }
    
    # Use DB.query to bypass ActiveRecord instantiation for raw site settings
    DB.query("SELECT name, value FROM site_settings WHERE name NOT IN (?) LIMIT 500", valid_settings)
      .map { |r| { id: r.name, name: r.name, value: r.value } }
  end
end