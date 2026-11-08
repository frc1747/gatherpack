# Checklist rows for the home page: to-do items the viewer can fix, and Your
# season. Which checklists and items show is decided by Checklists.checklist_for,
# so nothing here re-checks visibility.
module MyGatherpackChecklistsHelper
  # One checklist covering the viewer or one of their wards, with the items
  # still to do.
  SeasonEntry = Struct.new(:checklist, :subject, :ward, :done, :total, :open_items, keyword_init: true) do
    def percent
      total.zero? ? 0 : (done * 100.0 / total).floor
    end
  end

  UNFINISHED = %w[not_met pending].freeze

  # The viewer's to-do rows: each unfinished item they can fix, with its fix as
  # the button. A ward's row names the ward.
  def my_gatherpack_checklist_items
    my_gatherpack_checklist_results.flat_map do |subject, checklist, status|
      ward = my_gatherpack_ward_name(subject)
      status.explained.filter_map do |entry|
        next unless entry.full? && UNFINISHED.include?(entry.status)

        action, path = my_gatherpack_checklist_fix(checklist, entry, subject, ward: ward)
        next unless action

        MyGatherpack::Item.new(title: entry.item.label, detail: [ checklist.title, entry.summary, my_gatherpack_checklist_due(checklist, entry) ].compact_blank.join(" · "),
          at: entry.item.due_on || entry.item.ends_on || checklist.ends_on, path: path, action: action, icon: "list-check", ward: ward)
      end
    end
  end

  # Each checklist with something unfinished, for Your season.
  def my_gatherpack_season_entries
    my_gatherpack_checklist_results.filter_map do |subject, checklist, status|
      open_items = status.explained.select { |entry| entry.full? && UNFINISHED.include?(entry.status) }
      next if open_items.empty?

      counted = status.items.select { |entry| entry.full? && entry.item.counts? && !entry.exempt? }
      SeasonEntry.new(checklist: checklist, subject: subject, ward: my_gatherpack_ward_name(subject),
        done: counted.count(&:met?), total: counted.size, open_items: open_items)
    end
  end

  # "3 of 5" for a count item (one whose result carries confirmed and owed).
  def my_gatherpack_season_count(entry)
    measures = entry.measures || {}
    return unless measures["confirmed"] && measures["owed"]

    "#{number_with_precision(measures["confirmed"], precision: 2, strip_insignificant_zeros: true)} of #{number_with_precision(measures["owed"], precision: 2, strip_insignificant_zeros: true)}"
  end

  private

  # What a ward is called on a row: nil for the viewer themselves, otherwise
  # a name that is never blank, since the row's wording depends on it.
  def my_gatherpack_ward_name(subject)
    subject.first_name.presence || subject.identifier_name unless subject.id == current_user.person.id
  end

  # [[subject, checklist, status], ...] for the viewer and their wards, once a
  # request. An ended checklist is left out: its results are frozen, so
  # nothing the viewer does can finish an item on it.
  def my_gatherpack_checklist_results
    @my_gatherpack_checklist_results ||= begin
      viewer = current_user.person
      [ viewer, *viewer.wards ].flat_map do |subject|
        Checklists.checklist_for(subject, viewer: viewer).reject { |checklist, _| checklist.ended? }
          .map { |checklist, status| [ subject, checklist, status ] }
      end
    end
  end

  # The button's label and path, by the same rules as checklist_fix on the
  # person's checklists page: nothing when the viewer has no link to use. A
  # confirm fix posts, so its button links to that page.
  def my_gatherpack_checklist_fix(checklist, entry, subject, ward:)
    fix = entry.fix
    return if fix.blank? || !checklist_fix_allowed?(fix["requires"])
    # A pointer to what only a leader can finish is no to-do for anyone else.
    return if fix["by"] == "leader" && fix["requires"].blank? && fix["action"] != "attest" && !checklist.organizer?(current_user.person)

    if fix["action"] == "attest"
      item = (fix["item_id"] && checklist.checklist_items.find_by(id: fix["item_id"])) || entry.item
      attestation = ChecklistAttestation.new(person_id: subject.id)
      attestation.item = item
      return unless policy(attestation).create?

      label = ward && entry.acts_for == :guardian ? "Confirm for #{ward}" : (entry.acts_for == :self ? "I confirm" : "Confirm")
      [ label, person_checklists_path(subject) ]
    elsif fix["path"].present? && fix["path"].start_with?("/")
      [ fix["label"], fix["path"] ]
    end
  end

  def my_gatherpack_checklist_due(checklist, entry)
    date = entry.item.due_on || entry.item.ends_on || checklist.ends_on
    "Due #{l(date, format: :short)}" if date
  end
end
