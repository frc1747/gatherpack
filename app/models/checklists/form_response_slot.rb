module Checklists
  # One person's place on one form, whether or not they have a response yet.
  # A form item's fix links name it (by global id) so the link shows only to
  # viewers whose FormResponsePolicy lets them fill in or sign for that
  # person (Checklists::FormResponseSlotPolicy); the fix is checked when
  # shown, since a kind never depends on the viewer.
  class FormResponseSlot
    include GlobalID::Identification

    attr_reader :form, :subject

    def self.find(id)
      form_id, subject_id = id.to_s.split("_", 2)
      new(Form.find(form_id), Person.find(subject_id))
    end

    def initialize(form, subject)
      @form = form
      @subject = subject
    end

    def id
      "#{form.id}_#{subject.id}"
    end

    # The saved response, or an unsaved one for someone who hasn't started.
    def response
      @response ||= form.form_responses.includes(:form_submissions).find_or_initialize_by(subject: subject)
    end
  end
end
