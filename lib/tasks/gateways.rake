namespace :gateways do
  desc "Remove gateway secrets from audit log rows written before secrets were encrypted"
  task scrub_audit_log: :environment do
    Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/models/gateway").to_s)
    fields = Gateway.descendants.flat_map { |klass| klass.stored_attributes.fetch(:secrets, []) }.map(&:to_s).uniq

    # Older rows copied the whole configuration column, secrets included. It
    # is stored as a JSON string (or a hash).
    scrub_configuration = lambda do |configuration|
      case configuration
      when String then JSON.parse(configuration).except(*fields).to_json
      when Hash then configuration.except(*fields)
      else configuration
      end
    rescue JSON::ParserError
      configuration
    end

    scrubbed = 0
    AuditLog.where(item_type: "Gateway").find_each do |log|
      changes = {}

      object = log.object.present? ? PaperTrail.serializer.load(log.object) : nil
      if object.is_a?(Hash)
        scrubbed_object = object.except("secrets")
        scrubbed_object["configuration"] = scrub_configuration.call(object["configuration"]) if object.key?("configuration")
        changes[:object] = PaperTrail.serializer.dump(scrubbed_object) if scrubbed_object != object
      end

      object_changes = log.object_changes.present? ? PaperTrail.serializer.load(log.object_changes) : nil
      if object_changes.is_a?(Hash)
        scrubbed_changes = object_changes.except("secrets")
        scrubbed_changes["configuration"] = Array(object_changes["configuration"]).map(&scrub_configuration) if object_changes.key?("configuration")
        changes[:object_changes] = PaperTrail.serializer.dump(scrubbed_changes) if scrubbed_changes != object_changes
      end

      next if changes.empty?

      log.update_columns(changes)
      scrubbed += 1
    end

    puts "Removed gateway secrets from #{scrubbed} audit log #{"row".pluralize(scrubbed)}."
  end

  desc "Re-encrypt gateway secrets with the current encryption keys (run before changing SECRET_KEY_BASE)"
  task reencrypt: :environment do
    reencrypted = 0
    Gateway.find_each do |gateway|
      if gateway.secrets_unreadable?
        puts "Skipped #{gateway.class}##{gateway.id} (#{gateway.name}): its secrets can't be decrypted."
        next
      end

      gateway.encrypt
      reencrypted += 1
    rescue ActiveRecord::Encryption::Errors::Decryption => error
      Rails.logger.error("#{gateway.class}##{gateway.id} (#{gateway.name}) could not be re-encrypted: #{error.class}")
      puts "Skipped #{gateway.class}##{gateway.id} (#{gateway.name}): its secrets can't be decrypted."
    end

    puts "Re-encrypted the secrets of #{reencrypted} #{"gateway".pluralize(reencrypted)}."
  end
end
