module PluginCleaner
  class Cleaner
    # items: Array of { type:, id: } hashes coming from the frontend
    def self.delete!(items, performed_by:)
      results = []

      items.each do |item|
        type = item["type"]
        id   = item["id"]

        result = case type
                 when "user_custom_field"     then delete_custom_field(UserCustomField,     id)
                 when "topic_custom_field"    then delete_custom_field(TopicCustomField,    id)
                 when "post_custom_field"     then delete_custom_field(PostCustomField,     id)
                 when "category_custom_field" then delete_custom_field(CategoryCustomField, id)
                 when "group_custom_field"    then delete_custom_field(GroupCustomField,    id)
                 when "theme"                 then delete_theme(id)
                 when "badge"                 then delete_badge(id)
                 when "tag_group"             then delete_tag_group(id)
                 when "api_key"               then delete_api_key(id)
                 else
                   { success: false, error: "Unknown type: #{type}" }
                 end

        StaffActionLogger.new(performed_by).log_custom(
          "plugin_cleaner_delete",
          { type: type, id: id, result: result[:success] ? "deleted" : result[:error] }
        ) rescue nil

        results << { type: type, id: id }.merge(result)
      end

      results
    end

    private

    def self.delete_custom_field(model, field_name)
      # 1. Enforce Server-Side Validation against Core Fields
      if model == UserCustomField && PluginCleaner::Scanner::CORE_USER_FIELDS.include?(field_name)
        return { success: false, error: "Security violation: Cannot delete core user field" }
      end

      if model == TopicCustomField && PluginCleaner::Scanner::CORE_TOPIC_FIELDS.include?(field_name)
        return { success: false, error: "Security violation: Cannot delete core topic field" }
      end

      if model == PostCustomField && PluginCleaner::Scanner::CORE_POST_FIELDS.include?(field_name)
        return { success: false, error: "Security violation: Cannot delete core post field" }
      end

      # 2. Execute deletion if safe
      count = model.where(name: field_name).delete_all
      { success: true, deleted_count: count }
    rescue => e
      { success: false, error: e.message }
    end

    def self.delete_theme(id)
      theme = Theme.find_by(id: id)
      return { success: false, error: "Theme not found" } unless theme
      return { success: false, error: "Cannot delete default theme" } if theme.default?
      return { success: false, error: "Cannot delete active theme" } if theme.enabled? || theme.user_selectable

      theme.destroy!
      { success: true }
    rescue => e
      { success: false, error: e.message }
    end

    def self.delete_badge(id)
      badge = Badge.find_by(id: id)
      return { success: false, error: "Badge not found" }    unless badge
      return { success: false, error: "Cannot delete system badge" } if badge.system
      return { success: false, error: "Badge has grants — not safe to delete" } if badge.grant_count > 0

      badge.destroy!
      { success: true }
    rescue => e
      { success: false, error: e.message }
    end

    def self.delete_tag_group(id)
      tg = TagGroup.find_by(id: id)
      return { success: false, error: "Tag group not found" } unless tg
      return { success: false, error: "Tag group is not empty" } unless tg.tags.empty?

      tg.destroy!
      { success: true }
    rescue => e
      { success: false, error: e.message }
    end

    def self.delete_api_key(id)
      key = ApiKey.find_by(id: id)
      return { success: false, error: "API key not found" } unless key

      key.destroy!
      { success: true }
    rescue => e
      { success: false, error: e.message }
    end
  end
end
