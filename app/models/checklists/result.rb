module Checklists
  # One answer for one person and one item (or the overall): status is one of
  # Checklists::STATUSES. label overrides the status word ("Rookie",
  # "Excused", "Missed"). summary is short ("Holds Safety"), detail the full
  # sentence. measures are named numbers, fix the best next action as
  # { "label", "path", "action", "by" } (action "attest" carries "key"). by
  # says who acts on it: "person" (the person, or a guardian for a ward
  # where the item lets them), "guardian" (a guardian, or the person) or
  # "leader" (someone who runs the team or the checklist). An item pointing
  # at another checklist says who acts on what's left there. A group passing
  # up a child's fix adds the child's "item_id". A fix can
  # add "requires" => { "record" => global id, "query" => "update?" }: the
  # link shows only to viewers whose policy allows it, others see the label.
  Result = Struct.new(:status, :label, :summary, :detail, :measures, :fix, :excuse, keyword_init: true) do
    def initialize(**)
      super
      self.status = status.to_s
      self.measures ||= {}
    end

    STATUSES.each do |name|
      define_method(:"#{name}?") { status == name }
    end

    def self.met(summary = nil, **attributes) = new(status: "met", summary: summary, **attributes)
    def self.pending(summary = nil, **attributes) = new(status: "pending", summary: summary, **attributes)
    def self.not_met(summary = nil, **attributes) = new(status: "not_met", summary: summary, **attributes)
    def self.exempt(label, **attributes) = new(status: "exempt", label: label, summary: label, **attributes)
  end
end
