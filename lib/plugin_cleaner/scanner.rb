module PluginCleaner
  class Scanner
    # -------------------------------------------------------------------------
    # Dynamic Field Registration Lookup
    # -------------------------------------------------------------------------
    # Rather than hardcoding, we dynamically fetch fields registered by Discourse 
    # Core and active plugins to future-proof against Discourse upgrades.
    def self.dynamically_registered_fields
      user_fields = DiscoursePluginRegistry.serialized_current_user_fields.to_a +
                    DiscoursePluginRegistry.custom_user_fields.to_a
      
      # Include admin-defined User Profile fields (e.g. user_field_1)
      if defined?(UserField)
        user_fields += UserField.pluck(:id).map { |id| "user_field_#{id}" }
      end

      {
        user: user_fields.uniq.compact.map(&:to_s),
        topic: DiscoursePluginRegistry.topic_custom_fields.to_a.map(&:to_s),
        post: DiscoursePluginRegistry.post_custom_fields.to_a.map(&:to_s),
        category: DiscoursePluginRegistry.category_custom_fields.to_a.map(&:to_s),
        group: DiscoursePluginRegistry.group_custom_fields.to_a.map(&:to_s)
      }
    end

    # -------------------------------------------------------------------------
    # Heuristic Fallback (For Core fields that don't formally register)
    # -------------------------------------------------------------------------
    # Some legacy core fields bypass the registry. We maintain a minimal baseline,
    # but rely on the dynamic registry + threshold limits for true safety.
    BASELINE_USER_FIELDS = %w[
      seen_notification_id last_seen_notification_id
      notification_level_when_replying allowed_pm_users
      muted_usernames ignored_usernames homepage_id
      skip_new_user_tips read_first_notification
      sidebar_list_destination dismissed_sidebar_section_highlights_count
    ].freeze

    BASELINE_TOPIC_FIELDS = %w[featured_link external_id].freeze
    BASELINE_POST_FIELDS  = %w[notice action_code_who].freeze

    # -------------------------------------------------------------------------
    # Main entry point
    # -------------------------------------------------------------------------
    def self.run
      active_plugin_names = Discourse.plugins.map(&:name)
      
      # Respect the admin site setting for thresholds
      threshold = SiteSetting.plugin_cleaner_orphan_threshold rescue 5

      results = {
        active_plugins:         active_plugin_names,
        custom_fields:          safe { scan_custom_fields(threshold) },
        plugin_settings:        safe { scan_plugin_settings(active_plugin_names) },
        themes:                 safe { scan_themes },
        badges:                 safe { scan_badges },
        uploads:                safe { scan_uploads },
        web_hooks:              safe { scan_web_hooks },
        api_keys:               safe { scan_api_keys },
        tag_groups:             safe { scan_tag_groups },
        user_fields:            safe { scan_user_fields },
        watched_words:          safe { scan_watched_words },
        oauth_providers:        safe { scan_oauth_providers },
        cache:                  safe { scan_caches },
        scanned_at:             Time.now.utc.iso8601
      }

      results[:summary] = build_summary(results)
      results
    end

    # -------------------------------------------------------------------------
    # Custom Fields — all models
    # -------------------------------------------------------------------------
    def self.scan_custom_fields(threshold)
      {
        user:     field_counts(UserCustomField,     :user,     BASELINE_USER_FIELDS, threshold),
        topic:    field_counts(TopicCustomField,    :topic,    BASELINE_TOPIC_FIELDS, threshold),
        post:     field_counts(PostCustomField,     :post,     BASELINE_POST_FIELDS, threshold),
        category: field_counts(CategoryCustomField, :category, [], threshold),
        group:    (defined?(GroupCustomField) ? field_counts(GroupCustomField, :group, [], threshold) : [])
      }
    end

    def self.field_counts(model, type, baseline, threshold)
      registered_fields = dynamically_registered_fields[type] || []
      safe_list = (registered_fields + baseline).uniq

      model.group(:name).count
        .reject { |name, _| safe_list.include?(name.to_s) }
        .map do |name, count|
          is_orphan = count < threshold
          {
            id:      "#{model.name.underscore.tr('/', '_')}::#{name}",
            field:   name,
            model:   model.name,
            count:   count,
            orphan:  is_orphan,
            risk:    is_orphan ? risk_level(count) : "critical",
            deletable: true
          }
        end
        .sort_by { |x| [x[:orphan] ? 0 : 1, -x[:count]] }
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # Plugin Settings — detect settings from inactive/removed plugins
    # -------------------------------------------------------------------------
    def self.scan_plugin_settings(active_plugin_names)
      # Build prefix map: "discourse_ai" => active, "old_plugin" => inactive
      active_prefixes = active_plugin_names.map do |n|
        n.downcase.gsub(/^discourse[-_]/, "").gsub("-", "_")
      end

      SiteSetting.all_settings(defaults: true).filter_map do |s|
        name    = s[:setting].to_s
        plugin  = s[:plugin].to_s

        # Only include settings that belong to a specific plugin
        next if plugin.blank?

        is_active  = active_plugin_names.map(&:downcase).include?(plugin.downcase)
        at_default = s[:value].to_s == s[:default].to_s

        {
          id:           "setting::#{name}",
          setting:      name,
          value:        s[:value],
          default:      s[:default],
          plugin:       plugin,
          active:       is_active,
          at_default:   at_default,
          orphaned:     !is_active,
          deletable:    !is_active,
          risk:         is_active ? "low" : (at_default ? "low" : "medium")
        }
      end
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # Themes
    # -------------------------------------------------------------------------
    def self.scan_themes
      return [] unless defined?(Theme)

      Theme.includes(:remote_theme).map do |theme|
        remote    = theme.remote_theme
        orphaned  = !theme.enabled? && !theme.default? && !theme.user_selectable

        {
          id:              theme.id,
          name:            theme.name,
          active:          theme.enabled?,
          default:         theme.default?,
          user_selectable: theme.user_selectable,
          remote_url:      remote&.remote_url,
          last_updated:    remote&.updated_at&.iso8601,
          orphaned:        orphaned,
          deletable:       orphaned,
          risk:            orphaned ? "low" : "none"
        }
      end
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # Badges
    # -------------------------------------------------------------------------
    def self.scan_badges
      return [] unless defined?(Badge)

      Badge.all.map do |badge|
        orphaned = !badge.enabled && badge.grant_count == 0 && !badge.system

        {
          id:          badge.id,
          name:        badge.name,
          enabled:     badge.enabled,
          system:      badge.system,
          grant_count: badge.grant_count,
          orphaned:    orphaned,
          deletable:   orphaned,
          risk:        orphaned ? "low" : "none"
        }
      end
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # Uploads
    # -------------------------------------------------------------------------
    def self.scan_uploads
      return { checked: false } unless defined?(Upload)

      stale_days = SiteSetting.plugin_cleaner_stale_upload_days rescue 30
      total    = Upload.count
      conn     = ActiveRecord::Base.connection

      q = Upload.where("uploads.created_at < ?", stale_days.days.ago)
      q = q.where(access_control_post_id: nil) if conn.column_exists?(:uploads, :access_control_post_id)
      q = q.where.not(id: PostUpload.select(:upload_id))

      if defined?(UserAvatar) && conn.column_exists?(:user_avatars, :custom_upload_id)
        q = q.where.not(id: UserAvatar.select(:custom_upload_id).where.not(custom_upload_id: nil))
      end

      orphaned = q.count

      {
        checked:      true,
        total:        total,
        orphaned:     orphaned,
        orphaned_pct: total > 0 ? ((orphaned.to_f / total) * 100).round(1) : 0
      }
    rescue => e
      { checked: false, error: e.message }
    end

    # -------------------------------------------------------------------------
    # Webhooks
    # -------------------------------------------------------------------------
    def self.scan_web_hooks
      return [] unless defined?(WebHook)

      WebHook.all.map do |hook|
        last_event = defined?(WebHookEvent) ?
          WebHookEvent.where(web_hook_id: hook.id).order(created_at: :desc).first : nil

        failing = last_event && last_event.status.to_i >= 400

        {
          id:              hook.id,
          payload_url:     hook.payload_url,
          active:          hook.active,
          last_triggered:  last_event&.created_at&.iso8601,
          last_status:     last_event&.status,
          never_triggered: last_event.nil?,
          failing:         failing,
          orphaned:        failing || (!hook.active),
          deletable:       !hook.active,
          risk:            failing ? "high" : (hook.active ? "none" : "low")
        }
      end
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # API Keys
    # -------------------------------------------------------------------------
    def self.scan_api_keys
      return [] unless defined?(ApiKey)

      stale_days = SiteSetting.plugin_cleaner_stale_api_key_days rescue 90
      cols       = ApiKey.column_names
      has_last   = cols.include?("last_used_at")

      ApiKey.includes(:api_key_scopes, :user).map do |key|
        last_used = has_last ? key.last_used_at : nil
        stale     = last_used.nil? || last_used < stale_days.days.ago

        {
          id:          key.id,
          description: key.description.presence || "(no description)",
          user:        key.user&.username || "(global)",
          created_at:  key.created_at&.iso8601,
          last_used:   last_used&.iso8601,
          never_used:  last_used.nil?,
          scope_count: key.api_key_scopes.count,
          stale:       stale,
          orphaned:    stale,
          deletable:   stale,
          risk:        stale ? "medium" : "none"
        }
      end
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # Tag Groups
    # -------------------------------------------------------------------------
    def self.scan_tag_groups
      return [] unless defined?(TagGroup)

      TagGroup.includes(:tags).map do |tg|
        empty = tg.tags.empty?
        {
          id:        tg.id,
          name:      tg.name,
          tag_count: tg.tags.count,
          orphaned:  empty,
          deletable: empty,
          risk:      empty ? "low" : "none"
        }
      end
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # User profile fields
    # -------------------------------------------------------------------------
    def self.scan_user_fields
      return [] unless defined?(UserField)

      UserField.all.map do |uf|
        count = UserCustomField.where(name: "user_field_#{uf.id}").count
        empty = count == 0

        {
          id:           uf.id,
          name:         uf.name,
          field_type:   uf.field_type,
          required:     uf.required,
          filled_count: count,
          orphaned:     empty,
          deletable:    false,   # user fields are config, not safe to auto-delete
          risk:         empty ? "low" : "none"
        }
      end
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # Watched Words
    # -------------------------------------------------------------------------
    def self.scan_watched_words
      return [] unless defined?(WatchedWord)

      WatchedWord.group(:action).count.map do |action, count|
        label = WatchedWord.respond_to?(:actions) ?
          (WatchedWord.actions.key(action)&.to_s || action.to_s) : action.to_s
        { action: label, count: count }
      end
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # OAuth Providers
    # -------------------------------------------------------------------------
    def self.scan_oauth_providers
      return [] unless ActiveRecord::Base.connection.table_exists?("oauth2_user_infos")

      ActiveRecord::Base.connection
        .execute("SELECT provider, COUNT(*) as cnt FROM oauth2_user_infos GROUP BY provider")
        .map { |row| { provider: row["provider"], user_count: row["cnt"].to_i } }
    rescue => e
      []
    end

    # -------------------------------------------------------------------------
    # Cache sizes
    # -------------------------------------------------------------------------
    def self.scan_caches
      {
        stylesheets: safe_count(StylesheetCache, "created_at"),
        javascript:  safe_count(JavascriptCache, "updated_at")
      }
    end

    def self.safe_count(model, col)
      return {} unless defined?(model)
      {
        total: model.count,
        stale: model.where("#{col} < ?", 7.days.ago).count
      }
    rescue
      {}
    end

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    def self.build_summary(r)
      cf = r[:custom_fields] || {}

      orphaned_fields = %i[user topic post category group].sum do |k|
        (cf[k] || []).count { |f| f[:orphan] }
      end

      {
        orphaned_custom_fields:   orphaned_fields,
        orphaned_plugin_settings: (r[:plugin_settings] || []).count { |s| s[:orphaned] },
        inactive_themes:          (r[:themes]          || []).count { |t| t[:orphaned] },
        disabled_badges:          (r[:badges]          || []).count { |b| b[:orphaned] },
        stale_api_keys:           (r[:api_keys]        || []).count { |k| k[:stale] },
        failing_webhooks:         (r[:web_hooks]       || []).count { |w| w[:failing] },
        empty_tag_groups:         (r[:tag_groups]      || []).count { |t| t[:orphaned] },
        empty_user_fields:        (r[:user_fields]     || []).count { |f| f[:orphaned] },
        orphaned_uploads:         r.dig(:uploads, :orphaned) || 0
      }.tap { |s| s[:total_issues] = s.values.sum }
    end

    # -------------------------------------------------------------------------
    # Helpers
    # -------------------------------------------------------------------------
    def self.risk_level(count)
      case count
      when 0    then "critical"
      when 1..2 then "high"
      when 3..9 then "medium"
      else           "low"
      end
    end

    def self.safe
      yield
    rescue => e
      Rails.logger.warn "[PluginCleaner] Scanner error: #{e.message}"
      []
    end
  end
end