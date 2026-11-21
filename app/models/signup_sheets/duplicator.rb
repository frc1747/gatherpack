module SignupSheets
  # Copies a sheet's setup to a new sheet that isn't taking sign-ups yet: its
  # settings, positions with their rules, audience rules and organizers. The
  # dates, slots and sign-ups stay with the original.
  class Duplicator
    COPIED_ATTRIBUTES = %w[ team_id description contact event_type_id names_permission others_relationship_type_ids
      on_behalf_of_mode cancel_cutoff_hours reminder_days ].freeze

    def self.call(sheet, created_by:)
      new(sheet, created_by: created_by).call
    end

    def initialize(sheet, created_by:)
      @sheet = sheet
      @created_by = created_by
    end

    def call
      SignupSheet.transaction do
        copy = SignupSheet.create!(@sheet.attributes.slice(*COPIED_ATTRIBUTES)
          .merge(title: "#{@sheet.title} (copy)", status: :draft, created_by: @created_by))
        copy_positions(copy)
        copy_audience_rules(copy)
        copy_organizers(copy)
        copy
      end
    end

    private

    def copy_positions(copy)
      @sheet.signup_positions.each do |position|
        new_position = copy.signup_positions.create!(position.attributes.except("id", "signup_sheet_id", "created_at", "updated_at"))
        position.signup_position_rules.each do |rule|
          new_position.signup_position_rules.create!(rule.attributes.except("id", "signup_position_id", "created_at", "updated_at"))
        end
      end
    end

    def copy_audience_rules(copy)
      @sheet.signup_audience_rules.each do |rule|
        copy.signup_audience_rules.create!(rule.attributes.except("id", "signup_sheet_id", "created_at", "updated_at"))
      end
    end

    # The copier is already an organizer (the creator). Others are kept as
    # they were, whether or not they still hold a grant.
    def copy_organizers(copy)
      @sheet.signup_sheet_organizers.where.not(person_id: copy.signup_sheet_organizers.select(:person_id)).find_each do |organizer|
        copy.signup_sheet_organizers.build(person_id: organizer.person_id).save!(validate: false)
      end
    end
  end
end
