module PluginCleaner
  class Report
    def self.generate(scan_result)
      {
        timestamp:       Time.now.utc.iso8601,
        summary:         scan_result[:summary],
        recommendations: build_recommendations(scan_result),
        details:         build_details(scan_result)
      }
    end

    def self.build_recommendations(data)
      recs = []

      # Custom fields across all models
      cf = data[:custom_fields]
      %i[user topic post category group].each do |model|
        cf[model].select { |f| f[:orphan] }.each do |f|
          recs << {
            severity: f[:risk],
            type:     "orphan_custom_field",
            message:  "#{f[:model]} custom field '#{f[:field]}' has only #{f[:count]} #{"record".pluralize(f[:count])} — likely orphaned"
          }
        end
      end

      # Orphaned plugin settings
      data[:plugin_settings].select { |s| s[:orphaned] }.each do |s|
        recs << {
          severity: "medium",
          type:     "orphan_setting",
          message:  "Site setting '#{s[:setting]}' belongs to plugin '#{s[:plugin]}' which is not active"
        }
      end

      # Inactive themes
      data[:theme_fields].select { |t| t[:orphaned] }.each do |t|
        recs << {
          severity: "low",
          type:     "inactive_theme",
          message:  "Theme '#{t[:name]}' (id: #{t[:id]}) is inactive and not user-selectable — safe to remove"
        }
      end

      # Disabled badges with no grants
      data[:badge_issues].select { |b| b[:orphaned] }.each do |b|
        recs << {
          severity: "low",
          type:     "disabled_badge",
          message:  "Badge '#{b[:name]}' is disabled and has never been granted — safe to remove"
        }
      end

      # Stale API keys
      data[:api_keys].select { |k| k[:stale] }.each do |k|
        label = k[:never_used] ? "never used" : "last used over 90 days ago"
        recs << {
          severity: "medium",
          type:     "stale_api_key",
          message:  "API key '#{k[:description] || k[:id]}' (user: #{k[:user]}) is #{label} — consider revoking"
        }
      end

      # Failing webhooks
      data[:web_hooks].select { |w| w[:failing] }.each do |w|
        recs << {
          severity: "high",
          type:     "failing_webhook",
          message:  "Webhook to '#{w[:payload_url]}' is returning HTTP #{w[:last_status]} — check or remove"
        }
      end

      # Webhooks never triggered
      data[:web_hooks].select { |w| w[:never_triggered] && w[:active] }.each do |w|
        recs << {
          severity: "low",
          type:     "unused_webhook",
          message:  "Active webhook to '#{w[:payload_url]}' has never been triggered"
        }
      end

      # Empty tag groups
      data[:tag_groups].select { |t| t[:empty] }.each do |t|
        recs << {
          severity: "low",
          type:     "empty_tag_group",
          message:  "Tag group '#{t[:name]}' has no tags — safe to remove"
        }
      end

      # Empty user profile fields
      data[:user_fields].select { |f| f[:empty] }.each do |f|
        recs << {
          severity: "low",
          type:     "empty_user_field",
          message:  "User profile field '#{f[:name]}' (#{f[:field_type]}) has never been filled in"
        }
      end

      # Upload orphans
      if data[:upload_issues].is_a?(Hash) && data[:upload_issues][:orphaned].to_i > 0
        pct = data[:upload_issues][:orphaned_pct]
        recs << {
          severity: pct > 20 ? "high" : "medium",
          type:     "orphaned_uploads",
          message:  "#{data[:upload_issues][:orphaned]} uploads (#{pct}%) appear orphaned — run `rake uploads:clean` to reclaim space"
        }
      end

      recs.sort_by { |r| severity_order(r[:severity]) }
    end

    def self.build_details(data)
      {
        custom_fields:   data[:custom_fields],
        plugin_settings: data[:plugin_settings],
        themes:          data[:theme_fields],
        badges:          data[:badge_issues],
        uploads:         data[:upload_issues],
        web_hooks:       data[:web_hooks],
        api_keys:        data[:api_keys],
        tag_groups:      data[:tag_groups],
        user_fields:     data[:user_fields],
        watched_words:   data[:watched_words],
        cache:           {
          stylesheets: data[:stylesheet_cache],
          javascript:  data[:javascript_caches]
        }
      }
    end

    def self.severity_order(severity)
      { "critical" => 0, "high" => 1, "medium" => 2, "low" => 3 }.fetch(severity, 4)
    end
  end
end
