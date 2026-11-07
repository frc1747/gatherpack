module Checklists
  module Kinds
    # Someone recorded "this is done" (a ChecklistAttestation with the item's
    # key) within the item's dates. Who may attest is a setting: the person,
    # a guardian or the person, or a manager.
    class Attested < ItemKind
      WHO = [ [ "The person", "person" ], [ "A guardian, or the person", "guardian" ], [ "A manager", "manager" ] ].freeze

      class << self
        def label = "Confirmed"
        def description = "Someone confirms it's done"
        def uses_dates? = true

        def settings
          [
            ItemKind::Setting.new(key: :statement, type: :text, label: "Statement", hint: "What is confirmed, e.g. \"Handbook read\""),
            ItemKind::Setting.new(key: :key, type: :text, label: "Key", hint: "Optional. Items with the same key share confirmations; blank uses the statement"),
            ItemKind::Setting.new(key: :attested_by, type: :choice, label: "Who confirms", options: WHO)
          ]
        end

        def normalize_config(params)
          config = super
          config["attested_by"] = "person" unless WHO.map(&:last).include?(config["attested_by"])
          config["key"] = (config["key"].presence || config["statement"]).to_s.parameterize.presence
          config
        end

        def invalidations
          [ [ ::ChecklistAttestation, ->(attestation) { [ attestation.person_id ] } ] ]
        end

        def validate(item)
          item.errors.add(:base, "Write what is confirmed") if item.config["statement"].blank?
        end

        # A "within the last N" window moves at midnight.
        def next_change_at(item, context)
          relative = item.starts_within_amount.present? || (!Window.own_start?(item) && context.checklist.starts_within_amount.present?)
          context.as_of.to_date.tomorrow.in_time_zone.beginning_of_day if relative
        end

        def describe(item)
          who = WHO.find { |_, value| value == item.config["attested_by"] }&.first || "The person"
          "#{who} confirms: #{item.config["statement"]}"
        end
      end

      def evaluate(person_ids)
        attestations = ::ChecklistAttestation.where(person_id: person_ids, key: config["key"])
          .where(attested_at: window.start_time..window.end_time)
          .order(:attested_at).index_by(&:person_id)

        person_ids.index_with do |person_id|
          attestation = attestations[person_id]
          if attestation
            Result.met("Confirmed", detail: "#{config["statement"]}: confirmed #{I18n.l(attestation.attested_at.to_date, format: :long)}")
          else
            Result.not_met("Not confirmed", detail: "#{config["statement"]}: not confirmed yet",
              fix: { "label" => config["attested_by"] == "manager" ? "Ask a leader" : "I confirm", "action" => "attest", "key" => config["key"] })
          end
        end
      end
    end
  end
end
