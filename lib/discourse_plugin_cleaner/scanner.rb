module DiscoursePluginCleaner
  class Scanner
    def self.run
      {
        custom_fields: scan_custom_fields,
        site_settings: scan_site_settings
      }
    end

    def self.scan_custom_fields
      counts = UserCustomField.group(:name).count
      grouped = counts.map do |field_name, count|
        { field: field_name, count: count }
      end
      grouped.sort_by { |x| -x[:count] }
    end

    def self.scan_site_settings
      SiteSetting.all_settings.select do |setting|
        name = setting[:setting].to_s
        name.include?("plugin") || name.include?("custom")
      end
    end
  end
end