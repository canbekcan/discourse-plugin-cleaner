module PluginCleaner
  class Report
    def self.generate(scan_result)
      custom_fields = scan_result[:custom_fields]

      {
        timestamp: Time.now.utc.iso8601,
        summary: {
          total_custom_fields: custom_fields.length,
          suspicious_fields_count: custom_fields.count { |f| f[:count] < 5 },
          suspicious_fields: custom_fields.select { |f| f[:count] < 5 }
        },
        recommendation: build_recommendation(scan_result)
      }
    end

    def self.build_recommendation(data)
      data[:custom_fields].filter_map do |f|
        if f[:count] < 5
          "POTENTIAL ORPHAN: #{f[:field]} (#{f[:count]} #{"record".pluralize(f[:count])})"
        end
      end
    end
  end
end
