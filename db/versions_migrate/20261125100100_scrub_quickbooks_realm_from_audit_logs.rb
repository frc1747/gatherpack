# Audit log rows of gateways may hold a QuickBooks source's realm id and
# company name from when they were plain configuration. Removes those two
# keys (nothing else) from the stored object and changes. Not reversible
# beyond this: the values are gone, and the sources keep their own copies
# in their encrypted secrets.
class ScrubQuickbooksRealmFromAuditLogs < ActiveRecord::Migration[8.1]
  KEYS = %w[ realm_id company_name ].freeze

  def up
    conditions = KEYS.flat_map { |key| [ "object LIKE '%#{key}%'", "object_changes LIKE '%#{key}%'" ] }.join(" OR ")
    select_rows("SELECT id, object, object_changes FROM versions WHERE item_type = 'Gateway' AND (#{conditions})").each do |id, object, changes|
      execute "UPDATE versions SET object = #{quote(scrub(object))}, object_changes = #{quote(scrub(changes))} WHERE id = #{quote(id)}"
    end
  end

  def down
    # The scrubbed values can't come back.
  end

  private
    def scrub(text)
      return text if text.blank?

      data = PaperTrail.serializer.load(text)
      PaperTrail.serializer.dump(without_keys(data))
    end

    # The configuration is stored as a JSON string in older rows and as a
    # hash in newer ones.
    def without_keys(value)
      case value
      when Hash then value.except(*KEYS).transform_values { |item| without_keys(item) }
      when Array then value.map { |item| without_keys(item) }
      when String then without_keys_in_json(value)
      else value
      end
    end

    def without_keys_in_json(text)
      return text unless KEYS.any? { |key| text.include?(key) } && text.start_with?("{")

      parsed = JSON.parse(text)
      parsed.is_a?(Hash) ? parsed.except(*KEYS).to_json : text
    rescue JSON::ParserError
      text
    end
end
