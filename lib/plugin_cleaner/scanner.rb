module PluginCleaner
  class Scanner
    # Known core Discourse custom field names to exclude from orphan detection
    CORE_USER_FIELDS = %w[
      seen_notification_id
      last_seen_notification_id
      notification_level_when_replying
      allowed_pm_users
      muted_usernames
      ignored_usernames
      homepage_id
      skip_new_user_tips
    ].freeze

    CORE_TOPIC_FIELDS = %w[
      featured_link
      external_id
    ].freeze

    CORE_POST_FIELDS = %w[
      notice
      action_code_who
    ].freeze

    def self.run
      {
        custom_fields:          scan_custom_fields,
        site_settings:          scan_site_settings,
        theme_fields:           scan_theme_fields,
        badge_issues:           scan_badges,
        upload_issues:          scan_uploads,
        web_hooks:              scan_web_hooks,
        oauth_apps:             scan_oauth_apps,
        api_keys:               scan_api_keys,
        tag_groups:             scan_tag_groups,
        watched_words:          scan_watched_words,
        email_styles:           scan_email_styles,
        user_fields:            scan_user_fields,
        plugin_settings:        scan_plugin_site_settings,
        post_custom_fields:     scan_post_custom_fields,
        topic_custom_fields:    scan_topic_custom_fields,
        category_custom_fields: scan_category_custom_fields,
        group_custom_fields:    scan_group_custom_fields,
        stylesheet_cache:       scan_stylesheet_cache,
        javascript_caches:      scan_javascript_caches,
        summary:                nil
      }.tap { |r| r[:summary] = build_summary(r) }
    end

    # ---------------------------------------------------------------------------
    # Custom Fields
    # ---------------------------------------------------------------------------

    def self.scan_custom_fields
      {
        user:     scan_model_custom_fields(UserCustomField,     :name, CORE_USER_FIELDS),
        topic:    scan_model_custom_fields(TopicCustomField,    :name, CORE_TOPIC_FIELDS),
        post:     scan_model_custom_fields(PostCustomField,     :name, CORE_POST_FIELDS),
        category: scan_model_custom_fields(CategoryCustomField, :name, []),
        group:    scan_model_custom_fields(GroupCustomField,    :name, [])
      }
    end

    def self.scan_post_custom_fields
      scan_model_custom_fields(PostCustomField, :name, CORE_POST_FIELDS)
    end

    def self.scan_topic_custom_fields
      scan_model_custom_fields(TopicCustomField, :name, CORE_TOPIC_FIELDS)
    end

    def self.scan_category_custom_fields
      scan_model_custom_fields(CategoryCustomField, :name, [])
    end

    def self.scan_group_custom_fields
      scan_model_custom_fields(GroupCustomField, :name, [])
    end

    def self.scan_model_custom_fields(model, field_col, core_fields)
      model.group(field_col).count
        .reject { |name, _| core_fields.include?(name.to_s) }
        .map do |field_name, count|
          {
            field:  field_name,
            count:  count,
            model:  model.name,
            orphan: count < 5,
            risk:   risk_level(count)
          }
        end
        .sort_by { |x| x[:count] }
    end

    # ---------------------------------------------------------------------------
    # Site Settings
    # ---------------------------------------------------------------------------

    def self.scan_site_settings
      plugins = Discourse.plugins.map(&:name).map(&:downcase)

      SiteSetting.all_settings(defaults: true).filter_map do |setting|
        name = setting[:setting].to_s
        next unless name.include?("plugin") ||
                    name.include?("custom") ||
                    plugins.any? { |p| name.start_with?(p.gsub("-", "_")) }

        plugin_name = detect_plugin_for_setting(name, plugins)
        {
          setting:       name,
          value:         setting[:value],
          default:       setting[:default],
          at_default:    setting[:value].to_s == setting[:default].to_s,
          plugin:        plugin_name,
          plugin_active: plugin_name ? plugin_active?(plugin_name) : nil
        }
      end
    end

    def self.scan_plugin_site_settings
      active_plugin_names = Discourse.plugins.map(&:name).map(&:downcase)

      SiteSetting.all_settings(defaults: true).filter_map do |setting|
        name   = setting[:setting].to_s
        plugin = detect_plugin_for_setting(name, active_plugin_names)
        next unless plugin

        {
          setting:       name,
          value:         setting[:value],
          default:       setting[:default],
          plugin:        plugin,
          plugin_active: plugin_active?(plugin),
          orphaned:      !plugin_active?(plugin)
        }
      end
    end

    # ---------------------------------------------------------------------------
    # Themes
    # ---------------------------------------------------------------------------

    def self.scan_theme_fields
      return [] unless defined?(ThemeField)

      Theme.includes(:theme_fields, :remote_theme).map do |theme|
        remote = theme.remote_theme
        {
          id:              theme.id,
          name:            theme.name,
          active:          theme.enabled?,
          default:         theme.default?,
          user_selectable: theme.user_selectable,
          remote_url:      remote&.remote_url,
          last_updated:    remote&.updated_at,
          field_count:     theme.theme_fields.count,
          has_errors:      theme.theme_fields.where.not(error: [nil, ""]).exists?,
          orphaned:        !theme.enabled? && !theme.default? && !theme.user_selectable
        }
      end
    end

    # ---------------------------------------------------------------------------
    # Badges
    # ---------------------------------------------------------------------------

    def self.scan_badges
      return [] unless defined?(Badge)

      Badge.includes(:badge_type).map do |badge|
        {
          id:          badge.id,
          name:        badge.name,
          enabled:     badge.enabled,
          system:      badge.system,
          has_query:   badge.query.present?,
          grant_count: badge.grant_count,
          orphaned:    !badge.enabled && badge.grant_count == 0
        }
      end
    end

    # ---------------------------------------------------------------------------
    # Uploads
    # ---------------------------------------------------------------------------

    def self.scan_uploads
      return { checked: false, reason: "Upload table not available" } unless defined?(Upload)

      total    = Upload.count
      orphaned = Upload
        .where(access_control_post_id: nil)
        .where("created_at < ?", 30.days.ago)
        .where.not(id: PostUpload.select(:upload_id))
        .where.not(id: UserAvatar.select(:custom_upload_id).where.not(custom_upload_id: nil))
        .where.not(id: UserProfile.select(:profile_background_upload_id).where.not(profile_background_upload_id: nil))
        .where.not(id: UserProfile.select(:card_background_upload_id).where.not(card_background_upload_id: nil))
        .count

      {
        total:        total,
        orphaned:     orphaned,
        orphaned_pct: total > 0 ? ((orphaned.to_f / total) * 100).round(1) : 0
      }
    end

    # ---------------------------------------------------------------------------
    # Web Hooks
    # ---------------------------------------------------------------------------

    def self.scan_web_hooks
      return [] unless defined?(WebHook)

      WebHook.includes(:web_hook_event_types).map do |hook|
        last_event = WebHookEvent.where(web_hook_id: hook.id).order(created_at: :desc).first
        {
          id:              hook.id,
          payload_url:     hook.payload_url,
          active:          hook.active,
          last_triggered:  last_event&.created_at,
          last_status:     last_event&.status,
          never_triggered: last_event.nil?,
          failing:         last_event && last_event.status.to_i >= 400
        }
      end
    end

    # ---------------------------------------------------------------------------
    # OAuth Apps
    # ---------------------------------------------------------------------------

    def self.scan_oauth_apps
      return [] unless defined?(Oauth2UserInfo)

      Oauth2UserInfo.group(:provider).count.map do |provider, count|
        { provider: provider, user_count: count }
      end
    end

    # ---------------------------------------------------------------------------
    # API Keys
    # ---------------------------------------------------------------------------

    def self.scan_api_keys
      return [] unless defined?(ApiKey)

      ApiKey.includes(:api_key_scopes, :user).map do |key|
        last_used = ApiKeyRequest.where(api_key_id: key.id).maximum(:created_at) rescue nil
        {
          id:          key.id,
          description: key.description,
          user:        key.user&.username || "(global)",
          created_at:  key.created_at,
          last_used:   last_used,
          never_used:  last_used.nil?,
          scope_count: key.api_key_scopes.count,
          stale:       last_used.nil? || last_used < 90.days.ago
        }
      end
    end

    # ---------------------------------------------------------------------------
    # Tag Groups
    # ---------------------------------------------------------------------------

    def self.scan_tag_groups
      return [] unless defined?(TagGroup)

      TagGroup.includes(:tags).map do |tg|
        { id: tg.id, name: tg.name, tag_count: tg.tags.count, empty: tg.tags.empty? }
      end
    end

    # ---------------------------------------------------------------------------
    # Watched Words
    # ---------------------------------------------------------------------------

    def self.scan_watched_words
      return [] unless defined?(WatchedWord)

      WatchedWord.group(:action).count.map do |action, count|
        { action: WatchedWord.actions.key(action) || action, count: count }
      end
    end

    # ---------------------------------------------------------------------------
    # Email Styles
    # ---------------------------------------------------------------------------

    def self.scan_email_styles
      return {} unless defined?(EmailStyle)

      style = EmailStyle.first
      return { configured: false } unless style

      {
        configured:      true,
        has_custom_css:  style.css.present?,
        has_custom_html: style.html.present?,
        last_updated:    style.updated_at
      }
    end

    # ---------------------------------------------------------------------------
    # User Fields (custom profile fields)
    # ---------------------------------------------------------------------------

    def self.scan_user_fields
      return [] unless defined?(UserField)

      UserField.all.map do |uf|
        filled_count = UserCustomField.where(name: "user_field_#{uf.id}").count
        {
          id:           uf.id,
          name:         uf.name,
          field_type:   uf.field_type,
          required:     uf.required,
          filled_count: filled_count,
          empty:        filled_count == 0
        }
      end
    end

    # ---------------------------------------------------------------------------
    # Cache bloat
    # ---------------------------------------------------------------------------

    def self.scan_stylesheet_cache
      return {} unless defined?(StylesheetCache)

      { total: StylesheetCache.count, stale: StylesheetCache.where("created_at < ?", 7.days.ago).count }
    end

    def self.scan_javascript_caches
      return {} unless defined?(JavascriptCache)

      { total: JavascriptCache.count, stale: JavascriptCache.where("updated_at < ?", 7.days.ago).count }
    end

    # ---------------------------------------------------------------------------
    # Helpers
    # ---------------------------------------------------------------------------

    def self.risk_level(count)
      case count
      when 0      then "critical"
      when 1..2   then "high"
      when 3..9   then "medium"
      else             "low"
      end
    end

    def self.detect_plugin_for_setting(setting_name, plugin_names)
      plugin_names.find do |plugin|
        prefix = plugin.gsub("-", "_").gsub("discourse_", "").gsub("discourse-", "")
        setting_name.start_with?(prefix)
      end
    end

    def self.plugin_active?(plugin_name)
      Discourse.plugins.any? do |p|
        p.name.downcase == plugin_name.downcase ||
          p.name.downcase.gsub("-", "_") == plugin_name.downcase.gsub("-", "_")
      end
    end

    def self.build_summary(results)
      cf = results[:custom_fields]
      orphaned_fields = %i[user topic post category group].sum { |k| cf[k].count { |f| f[:orphan] } }

      s = {
        orphaned_custom_fields:   orphaned_fields,
        orphaned_plugin_settings: results[:plugin_settings].count { |s| s[:orphaned] },
        inactive_themes:          results[:theme_fields].count { |t| t[:orphaned] },
        disabled_badges:          results[:badge_issues].count { |b| b[:orphaned] },
        stale_api_keys:           results[:api_keys].count { |k| k[:stale] },
        failing_webhooks:         results[:web_hooks].count { |w| w[:failing] },
        empty_tag_groups:         results[:tag_groups].count { |t| t[:empty] },
        empty_user_fields:        results[:user_fields].count { |f| f[:empty] },
        orphaned_uploads:         results[:upload_issues].is_a?(Hash) ? (results[:upload_issues][:orphaned] || 0) : 0
      }
      s[:total_issues] = s.values.sum
      s
    end
  end
end
