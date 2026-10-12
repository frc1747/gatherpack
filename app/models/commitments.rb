# Credit source kinds for commitments. A kind is the extension point of the
# commitments layer: it turns some activity (check-ins, sign-ups, …) into
# credit records for a commitment's owing people. Kinds register from an
# initializer, so a branch can add one without touching this code:
#
#   Commitments.register_source(:checkins, Commitments::CheckinSource)
#
# A source whose kind isn't registered shows as unavailable and counts nothing.
module Commitments
  # One unit of activity attributed to a person. state is :planned or
  # :confirmed. Records with the same person and dedupe_key count once per
  # commitment, from the first source in the commitment's order (a nil key
  # never dedupes). label and link describe the record in the breakdown.
  CreditRecord = Struct.new(:person_id, :quantity, :state, :date, :dedupe_key, :label, :link, keyword_init: true) do
    def confirmed?
      state == :confirmed
    end
  end

  # A line for a person's commitment page ("Check in at any Outreach event"),
  # with links as [label, record or path] pairs (upcoming events, a sheet, …).
  HowToEarn = Struct.new(:text, :links, keyword_init: true)

  @sources = {}

  class << self
    def register_source(kind, klass)
      @sources[kind.to_s] = klass
    end

    def unregister_source(kind)
      @sources.delete(kind.to_s)
    end

    # The kind's class, or nil when it isn't registered.
    def source_kind(kind)
      @sources[kind.to_s]
    end

    def source_kinds
      @sources.dup
    end

    # The dedupe key every kind uses for "this person did something at this
    # event": event_id, and worker_id for who actually did it (who checked in,
    # who took the place). A sign-up and a check-in by the same worker count
    # once; two people working for the same person count twice.
    def event_key(event_id, worker_id)
      "Event:#{event_id}:Person:#{worker_id}"
    end
  end
end
