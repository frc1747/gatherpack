module Signups
  # How a sheet's age rules apply between one viewer and the people they
  # look at or place (SignupPositionRule#check_for), worked out once per
  # person. Build one per page or placement: the roster checks every row
  # against the same viewer.
  class AgeCheck
    def initialize(sheet, viewer)
      @sheet = sheet
      @viewer = viewer
      @modes = {}
    end

    # :shown    the viewer may see the result (SignupPositionRule.age_visible_to?)
    # :unchecked an organizer who may not; the rule isn't checked
    # :family   an organizer's family through a type members add themselves;
    #           this organizer can't place them, whatever their age
    # :hidden   anyone else who may not see it; told only pass or fail
    def mode_for(person)
      @modes[person.id] ||=
        if SignupPositionRule.age_visible_to?(@viewer, person) then :shown
        elsif !organizer? || SignupSheet.trusted_relative?(@viewer, person) then :hidden
        elsif @sheet.self_or_relative?(@viewer, person) then :family
        else :unchecked
        end
    end

    private

    def organizer?
      @organizer = @sheet.organizer?(@viewer) unless defined?(@organizer)
      @organizer
    end
  end
end
