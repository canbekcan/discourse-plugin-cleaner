module PluginCleaner
  class Report

    def self.generate(scan_result)
      custom_fields = scan_result[:custom_fields]

      {
        # BUG FIX 3: Time.now returns a Ruby Time object which is not JSON-serializable
        # in a consistent, readable format. Use ISO 8601 instead.
        timestamp: Time.zone.now.iso8601,

        summary: {
          total_custom_fields: custom_fields.length,

          # BUG FIX 4: .select returns an Array of hashes here, but the original code
          # called .length on it later expecting an integer count — this works, but
          # naming it "suspicious_fields" and returning the full array is misleading
          # and bloats the JSON. Return both the count and the list separately.
          suspicious_fields_count: custom_fields.count { |f| f[:count] < 5 },
          suspicious_fields: custom_fields.select { |f| f[:count] < 5 }
        },

        recommendation: build_recommendation(scan_result)
      }
    end

    def self.build_recommendation(data)
      data[:custom_fields].map do |f|
        # BUG FIX 5: Threshold of < 3 silently drops fields with count 3 or 4 from
        # recommendations even though they were flagged as suspicious (< 5) in the
        # summary above. This creates an inconsistency in the report.
        # Align the recommendation threshold with the suspicious threshold (< 5),
        # and include count in the message to aid decision-making.
        if f[:count] < 5
          "POTENTIAL ORPHAN: #{f[:field]} (#{f[:count]} #{"record".pluralize(f[:count])})"
        end
      end.compact
    end
  end
end
