module Checklists
  # access is :full or :status. At :status only status, word and label are
  # filled; summary, detail, measures and fix are nil. excuse is
  # { by:, at:, reason: } with reason only for managers and admins.
  ItemStatus = Struct.new(:item, :label, :status, :word, :summary, :detail, :measures, :fix, :acts_for, :excuse,
    :access, :changed_at, :stale, :children, keyword_init: true) do
    def all_children
      Array(children).flat_map { |child| [ child ] + child.all_children }
    end

    # The word to show: the kind's label ("Rookie", "Missed") or the status word.
    def text
      label.presence || word
    end

    def full?
      access == :full
    end

    Checklists::STATUSES.each do |name|
      define_method(:"#{name}?") { status == name }
    end
  end
end
