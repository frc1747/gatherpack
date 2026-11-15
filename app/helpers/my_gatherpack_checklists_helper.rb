# Checklist rows for the home page: to-do items the viewer can fix, and My
# Season. Which checklists and items show is decided by Checklists.checklist_for,
# so nothing here re-checks visibility. Each item shows once: in To do when the
# viewer can fix it, otherwise in My Season, in words rather than numbers.
module MyGatherpackChecklistsHelper
  # One checklist covering the viewer or one of their wards, with its items.
  SeasonEntry = Struct.new(:checklist, :subject, :ward, :items, keyword_init: true)

  # One item's line in My Season. path is where its detail links.
  SeasonLine = Struct.new(:entry, :checklist, :subject, :ward, :path, keyword_init: true) do
    def key
      [ subject.id, entry.item.id ]
    end
  end

  # My Season's lines: unfinished ones the viewer can't fix now, and done
  # ones (met or exempt).
  Season = Struct.new(:in_progress, :done, keyword_init: true) do
    def any?
      in_progress.any? || done.any?
    end
  end

  UNFINISHED = %w[not_met pending].freeze

  # The viewer's to-do rows: each unfinished item they can fix, with its fix as
  # the button. A ward's row names the ward.
  def my_gatherpack_checklist_items
    my_gatherpack_checklist_todos.map do |todo|
      checklist, entry, action, path = todo.values_at(:checklist, :entry, :action, :path)

      # A "Next: ..." fix names a particular shift: that belongs in the detail, not on a button.
      next_up = action.delete_prefix("Next: ") if action.start_with?("Next: ")
      action = "Sign up" if next_up

      MyGatherpack::Item.new(title: entry.item.label, detail: [ (checklist.title unless checklist.title == entry.item.label), entry.summary, next_up, my_gatherpack_checklist_due(checklist, entry) ].compact_blank.join(" · "),
        at: entry.item.due_on || entry.item.ends_on || checklist.ends_on, path: path, action: action, icon: "list-check", ward: todo[:ward])
    end
  end

  # Each checklist the viewer can see items on: everything on it, unfinished
  # first, so finished work shows too.
  def my_gatherpack_season_entries
    entries = my_gatherpack_checklist_results.filter_map do |subject, checklist, status|
      items = status.explained.select(&:full?)
      next if items.empty?

      SeasonEntry.new(checklist: checklist, subject: subject, ward: my_gatherpack_ward_name(subject), items: items)
    end
    my_gatherpack_without_repeats(entries)
  end

  # My Season: every item that isn't a to-do row, grouped by whether it's done.
  def my_gatherpack_season
    @my_gatherpack_season ||= begin
      todo = my_gatherpack_checklist_todos.map { |row| [ row[:subject].id, row[:entry].item.id ] }.to_set
      lines = my_gatherpack_season_entries.flat_map do |season_entry|
        path = season_entry.ward ? person_checklists_path(season_entry.subject) : checklist_path(season_entry.checklist)
        season_entry.items.map do |entry|
          SeasonLine.new(entry: entry, checklist: season_entry.checklist, subject: season_entry.subject, ward: season_entry.ward,
            path: my_gatherpack_season_item_path(season_entry, entry, path))
        end
      end
      lines.reject! { |line| todo.include?(line.key) }
      in_progress, done = lines.partition { |line| UNFINISHED.include?(line.entry.status) }
      Season.new(in_progress: in_progress, done: done.sort_by.with_index { |line, index| [ line.entry.exempt? ? 1 : 0, index ] })
    end
  end

  # What a My Season line says after the item's title, in words: what the
  # person did once met ("44 h this fall", "5 events"), the gap while not
  # ("3.5 more hours by Dec 31"), or the status word when nothing is
  # measured. An exempt item gives its label ("Rookie"). A count owed
  # together says "for your family". An item standing for a checklist that
  # doesn't cover the subject says "Not required for you", never its title.
  def my_gatherpack_season_answer(entry, subject: current_user.person)
    return "Not required for you" if my_gatherpack_uncovered_checklist?(entry, subject)
    return entry.text if entry.exempt?

    family = " for your family" if entry.item.config["group_relationship_type_id"].present?
    if entry.met?
      done = my_gatherpack_season_done(entry)
      return entry.text unless done

      [ "#{done}#{family}", my_gatherpack_season_name(entry.item) ].compact.join(" ")
    else
      gap = my_gatherpack_season_gap(entry)
      return entry.text unless gap

      due = " by #{entry.item.due_on.strftime("%b %-d")}" if entry.item.due_on
      "#{gap}#{family}#{due}"
    end
  end

  # The detail a My Season line shows when tapped: what the checklists page
  # shows for the item, unless that would name a checklist that doesn't
  # cover the subject.
  def my_gatherpack_season_detail(entry, subject: current_user.person)
    entry.detail.presence || entry.summary unless my_gatherpack_uncovered_checklist?(entry, subject)
  end

  # "3 of 5" for an item that measures progress (its result carries confirmed
  # and owed), with " h" when the kind measures hours. Home says this in
  # words instead (my_gatherpack_season_answer); the family page still reads
  # the numbers.
  def my_gatherpack_season_count(entry)
    measures = entry.measures || {}
    return unless measures["confirmed"] && measures["owed"]

    hours = my_gatherpack_measure_hours?(entry.item, "owed")
    "#{my_gatherpack_number(measures["confirmed"])} of #{my_gatherpack_number(measures["owed"])}#{" h" if hours}"
  end

  # Where a My Season line links: an item that is another checklist goes to
  # that checklist (for the viewer's own row, and only when that checklist
  # covers them too), anything else to the row's own page.
  def my_gatherpack_season_item_path(entry, item, row_path)
    return row_path if entry.ward || item.item.kind != "checklist"

    other = my_gatherpack_season_others[item.item.config["checklist_id"]]
    other && my_gatherpack_checklist_ids_for(entry.subject).include?(other.id) ? checklist_path(other) : row_path
  end

  # The forms the subject's checklist items list ("form_ids"), as shown on
  # Home, so the forms section can leave those out (MyGatherpack::Claims).
  def my_gatherpack_checklist_form_ids(subject)
    my_gatherpack_checklist_results.select { |row_subject, _, _| row_subject.id == subject.id }.flat_map do |_, _, status|
      status.items.select(&:full?).flat_map { |entry| [ entry ] + entry.all_children }
        .flat_map { |entry| Array(entry.item.config["form_ids"]) }
    end.compact_blank.map(&:to_s).uniq
  end

  private

  # Whether the item stands for another checklist that doesn't cover the
  # subject: its result names that checklist ("Not on ..."), which Home
  # mustn't.
  def my_gatherpack_uncovered_checklist?(entry, subject)
    entry.item.kind == "checklist" && !my_gatherpack_checklist_ids_for(subject).include?(entry.item.config["checklist_id"])
  end

  # The unfinished items the viewer can fix, as { subject:, checklist:,
  # entry:, ward:, action:, path: }, once a request.
  def my_gatherpack_checklist_todos
    @my_gatherpack_checklist_todos ||= my_gatherpack_checklist_results.flat_map do |subject, checklist, status|
      ward = my_gatherpack_ward_name(subject)
      status.explained.filter_map do |entry|
        next unless entry.full? && UNFINISHED.include?(entry.status)
        # Another checklist's line repeats that checklist's own rows, fix included.
        next if entry.item.kind == "checklist" && my_gatherpack_checklist_ids_for(subject).include?(entry.item.config["checklist_id"])

        action, path = my_gatherpack_checklist_fix(checklist, entry, subject, ward: ward)
        next unless action

        { subject: subject, checklist: checklist, entry: entry, ward: ward, action: action, path: path }
      end
    end
  end

  # What the person did on a met, measured item, with its unit ("44 h",
  # "5 events"). Attendance's confirmed stops at the minimum (it's progress
  # toward it), so its credited hours, the person's own, come first.
  def my_gatherpack_season_done(entry)
    measures = entry.measures || {}
    key = %w[credited confirmed].find { |name| measures[name] }
    return unless key

    value = measures[key]
    if my_gatherpack_measure_hours?(entry.item, key)
      "#{my_gatherpack_number(value)} h"
    else
      [ my_gatherpack_number(value), my_gatherpack_unit(entry.item, value) ].compact.join(" ")
    end
  end

  # How much is still owed, with its unit ("3.5 more hours", "1 more
  # shift"): the result's remaining, or owed less confirmed. Nil when there's
  # nothing measured or nothing left (pending on what's planned).
  def my_gatherpack_season_gap(entry)
    measures = entry.measures || {}
    remaining = measures["remaining"]
    remaining ||= measures["owed"].to_f - measures["confirmed"].to_f if measures["owed"] && measures["confirmed"]
    return unless remaining && remaining.to_f.positive?

    unit = my_gatherpack_measure_hours?(entry.item, "owed") ? (remaining.to_f == 1 ? "hour" : "hours") : my_gatherpack_unit(entry.item, remaining)
    [ my_gatherpack_number(remaining), "more", unit ].compact.join(" ")
  end

  # "this fall": the name of the item's rule group in force today (an
  # attendance item's rules), or "this season" when that group has no name
  # of its own. Nil for an item without rules.
  def my_gatherpack_season_name(item)
    kind = item.kind_class
    return unless kind.respond_to?(:rules) && Array(item.config["rules"]).any?

    today = Date.current
    rule = kind.rules(item).find { |candidate| (candidate.starts_on.nil? || candidate.starts_on <= today) && (candidate.ends_on.nil? || candidate.ends_on >= today) }
    name = Array(item.config["rules"])[rule.index]["name"].to_s.strip if rule
    return "this season" if name.blank?

    # "Fall" reads "this fall"; a name with capitals inside ("FRC season") keeps them.
    "this #{name.split.all? { |word| word == word.capitalize } ? name.downcase : name}"
  end

  def my_gatherpack_measure_hours?(item, key)
    Array(item.kind_class&.measures).any? { |measure| measure.key.to_s == key && measure.type == :hours }
  end

  # The item's unit ("shifts"), singular for one.
  def my_gatherpack_unit(item, value)
    unit = item.config["unit"].to_s.strip.presence
    unit && (value.to_f == 1 ? unit.singularize : unit)
  end

  def my_gatherpack_number(value)
    number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
  end

  # Leaves out a one-item checklist that another of the same person's
  # checklists already shows as a line ("Another checklist" item): that line
  # says the same. A checklist with several items keeps its own lines, since
  # the one line can't show them.
  def my_gatherpack_without_repeats(entries)
    shown = entries.each_with_object(Hash.new { |hash, key| hash[key] = Set.new }) do |entry, ids|
      entry.items.each { |item| ids[entry.subject.id] << item.item.config["checklist_id"] if item.item.kind == "checklist" }
    end
    entries.reject { |entry| entry.items.one? && shown[entry.subject.id].include?(entry.checklist.id) }
  end

  # The checklists My Season lines point to, by id, in one query.
  def my_gatherpack_season_others
    @my_gatherpack_season_others ||= begin
      ids = my_gatherpack_checklist_results.flat_map { |_, _, status| status.explained.map(&:item) }
        .select { |item| item.kind == "checklist" }.map { |item| item.config["checklist_id"] }.compact.uniq
      Checklist.where(id: ids).index_by(&:id)
    end
  end

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
    elsif fix["by"] == "leader" && checklist.organizer?(current_user.person)
      # Something only a leader can do, for one: the checklist is where they act on it.
      [ fix["label"], checklist_path(checklist) ]
    end
  end

  # The ids of the checklists the subject has rows on.
  def my_gatherpack_checklist_ids_for(subject)
    @my_gatherpack_checklist_ids_for ||= my_gatherpack_checklist_results.group_by(&:first).transform_values { |rows| rows.map { |row| row.second.id }.to_set }
    @my_gatherpack_checklist_ids_for.fetch(subject, Set.new)
  end

  def my_gatherpack_checklist_due(checklist, entry)
    date = entry.item.due_on || entry.item.ends_on || checklist.ends_on
    "Due #{l(date, format: :short)}" if date
  end
end
