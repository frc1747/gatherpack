module Housekeeping
  # What "Archive selected" or "Restore selected" would do, before it's done:
  # the records it would change and those it skips, with why.
  #
  #   preview = Housekeeping::Preview.new(type, :archive, records, user)
  #   preview.sentence   # "3 events will be archived. 1 skipped."
  #   preview.skipped    # [Skip(record, "still used by Trip 2027")]
  #   preview.apply!     # => the records changed
  class Preview
    ACTIONS = %i[archive restore].freeze

    Skip = Struct.new(:record, :reason)

    attr_reader :type, :action, :ready, :skipped

    def initialize(type, action, records, user)
      raise ArgumentError, "unknown action #{action}" unless ACTIONS.include?(action.to_sym)

      @type = type
      @action = action.to_sym
      @ready = []
      @skipped = []
      records.each do |record|
        reason = skip_reason(record, user)
        reason ? @skipped << Skip.new(record, reason) : @ready << record
      end
    end

    def sentence
      done = archive? ? "archived" : "restored"
      text = "#{count_of(ready.size)} will be #{done}."
      text += " #{skipped.size} skipped." if skipped.any?
      text
    end

    # Changes the ready records, all or none.
    def apply!
      type.model.transaction do
        ready.each { |record| archive? ? type.archive!(record) : type.restore!(record) }
      end
      ready
    end

    private

    def archive?
      action == :archive
    end

    def count_of(size)
      "#{size} #{size == 1 ? type.label.downcase.singularize : type.label.downcase}"
    end

    def skip_reason(record, user)
      archived = type.archived?(record)
      return "already archived" if archive? && archived
      return "not archived" if !archive? && !archived
      return "you can't change it" unless type.permitted?(user, record, action)

      used = archive? ? type.used_by(record) : []
      "still used by #{used.to_sentence}" if used.any?
    end
  end
end
