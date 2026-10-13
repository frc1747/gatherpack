module Commitments
  # Sign-ups to one position on a sheet ("Cashier" on Snack Stand); see
  # SignupSource. A kind of its own because a kind has one subject type.
  class SignupPositionSource < SignupSource
    def self.label
      "Sign-ups for a position"
    end

    def self.subject_type
      "SignupPosition"
    end

    # Positions on the sheets the person also organizes.
    def self.subject_choices(_commitment, person)
      SignupPosition.where(signup_sheet_id: organized_sheet_ids(person)).joins(:signup_sheet)
        .order("signup_sheets.title", :position, :created_at)
    end

    def self.sheet_of(subject)
      subject.signup_sheet
    end

    def how_to_earn
      HowToEarn.new(text: "Sign up as #{source.subject&.name} on #{sheet&.title}", links: open_dates)
    end

    def sheet
      source.subject&.signup_sheet
    end

    private

    def positions
      SignupPosition.where(id: source.subject_id)
    end
  end
end
