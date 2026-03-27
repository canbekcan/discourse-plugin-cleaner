module PluginCleaner
  class Scanner

    def self.run
      {
        custom_fields: scan_custom_fields,
        site_settings: scan_site_settings
      }
    end

    def self.scan_custom_fields
      # BUG FIX 1: N+1 query — was doing a separate COUNT query per field name.
      # Use GROUP + COUNT in a single query instead.
      counts = UserCustomField
        .group(:name)
        .count # => { "field_name" => 42, ... }

      grouped = counts.map do |field_name, count|
        { field: field_name, count: count }
      end

      grouped.sort_by { |x| -x[:count] }
    end

    def self.scan_site_settings
      # BUG FIX 2: SiteSetting.all_settings returns an Array of hashes, not a Hash.
      # Calling .select { |k, _| } on an Array of hashes destructures each hash as
      # a [key, value] pair only if it's a two-element array — which it isn't here.
      # Correct approach: use the hash form via SiteSetting.all_settings(defaults: true)
      # which returns a Hash, then filter on the key.
      SiteSetting.all_settings.select do |setting|
        name = setting[:setting].to_s
        name.include?("plugin") || name.include?("custom")
      end
    end
  end
end
