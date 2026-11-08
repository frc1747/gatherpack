# The family page's rows, ward by ward. Each comes from the helper or policy
# behind that ward's own pages, so the two always agree.
module FamilyHelper
  # +checklists+ is [[checklist, status], ...]; +needs_you+ counts what the
  # viewer can act on, by the same rules as the home page's To do.
  Card = Struct.new(:ward, :name, :forms, :signups, :checklists, :events, :needs_you, keyword_init: true) do
    def empty?
      [ forms, signups, checklists, events ].all?(&:empty?)
    end
  end

  # One card per ward, in name order.
  def family_cards
    @family_cards ||= begin
      viewer = current_user.person
      forms = family_form_entries(viewer)
      wards = viewer.wards.to_a.sort_by { |ward| [ family_ward_name(ward).downcase, ward.id ] }
      signups = family_signups(wards)

      wards.map do |ward|
        checklists = family_checklists(ward, viewer)
        Card.new(ward: ward, name: family_ward_name(ward), forms: forms.fetch(ward.id, []), signups: signups.fetch(ward.id, []),
          checklists: checklists, events: family_events(ward), needs_you: family_needs_you(ward, forms.fetch(ward.id, []), checklists))
      end
    end
  end

  def family_card_heading(card)
    return "All caught up" if card.needs_you.zero?

    "#{pluralize(card.needs_you, "thing")} #{card.needs_you == 1 ? "needs" : "need"} you"
  end

  def family_form_item(entry)
    action = if entry.needs_viewer_signature? then "Sign"
    elsif entry.to_do? then "Fill out"
    else "View"
    end
    MyGatherpack::Item.new(title: entry.form.title, detail: [ form_due(entry.form), FormsHelper::STATUS_LABELS[entry.status] ].compact.join(" · "),
      at: (entry.form.closes_at if entry.to_do?), path: form_entry_path(entry), action: action, icon: "file-signature")
  end

  def family_signup_item(signup)
    MyGatherpack::Item.new(title: signup.signup_position.name, detail: [ my_gatherpack_signup_time(signup.event), signup.signup_sheet.title ].join(" · "),
      at: signup.event.start_time, path: signup_sheet_path(signup.signup_sheet))
  end

  def family_checklist_item(card, checklist, status)
    open_items = status.explained.select { |entry| MyGatherpackChecklistsHelper::UNFINISHED.include?(entry.status) }
    MyGatherpack::Item.new(title: checklist.title, detail: [ status.overall&.text, open_items.map { |entry| entry.item.label }.to_sentence.presence ].compact.join(" · "),
      path: person_checklists_path(card.ward), action: "Open", icon: "list-check")
  end

  def family_event_detail(row)
    times = [ row.start_time.strftime("%-I:%M %p"), row.end_time&.strftime(row.end_time.to_date == row.start_time.to_date ? "%-I:%M %p" : "%b %-d, %-I:%M %p") ].compact.join(" – ")
    [ times, row.location.presence ].compact.join(" · ")
  end

  # Pooled count items on running checklists. Wards pooled together share one
  # result, so they share one row.
  def family_owed_items(cards = family_cards)
    owed = cards.flat_map do |card|
      card.checklists.reject { |checklist, _| checklist.ended? }.flat_map do |checklist, status|
        status.all_items.select { |entry| family_pooled_count?(entry) }.map { |entry| [ card, checklist, entry ] }
      end
    end

    owed.group_by { |_card, _checklist, entry| [ entry.item.id, entry.measures ] }.values.map do |rows|
      card, checklist, entry = rows.first
      MyGatherpack::Item.new(title: entry.item.label, detail: [ checklist.title, my_gatherpack_season_count(entry), entry.text, rows.map { |row| row.first.name }.to_sentence ].compact_blank.join(" · "),
        path: person_checklists_path(card.ward), action: "Open", icon: "users")
    end
  end

  private

  def family_ward_name(ward)
    ward.first_name.presence || ward.identifier_name
  end

  # { ward_id => entries }, what the viewer can do first.
  def family_form_entries(viewer)
    return {} unless GatherPack::Features.enabled?(:forms)

    ward_form_entries(viewer, viewer).group_by { |entry| entry.subject.id }.transform_values do |entries|
      entries.sort_by.with_index { |entry, index| [ entry.to_do? ? 0 : 1, index ] }
    end
  end

  # { ward_id => upcoming sign-ups }, as SignupsSummary finds them for a person
  # and on sheets the viewer may see.
  def family_signups(wards)
    return {} unless GatherPack::Features.enabled?(:signups)

    ids = wards.map(&:id)
    signups = Signup.active.joins(signup_slot: :event).where("COALESCE(events.end_time, events.start_time) >= ?", Time.current)
    found = signups.where(person_id: ids).or(signups.where(on_behalf_of_id: ids)).or(signups.where(signed_up_by_id: ids, placed_by_organizer: false))
      .includes(signup_slot: [ :event, { signup_position: :signup_sheet } ]).to_a
    visible = found.map(&:signup_sheet).uniq.select { |sheet| policy(sheet).show? }
    found = found.select { |signup| visible.include?(signup.signup_sheet) }.sort_by { |signup| [ signup.event.start_time, signup.signup_sheet.title ] }

    ids.index_with { |id| found.select { |signup| [ signup.person_id, signup.on_behalf_of_id, (signup.signed_up_by_id unless signup.placed_by_organizer) ].include?(id) } }
  end

  # The same list as the ward's Checklists tab: Checklists.checklist_for reads
  # each through status_for, which applies each item's "who sees it".
  def family_checklists(ward, viewer)
    return [] unless Checklists.enabled?

    Checklists.checklist_for(ward, viewer: viewer)
  end

  def family_events(ward)
    return [] unless GatherPack::Features.enabled?(:events)

    MyGatherpack::WardEvents.new(ward, viewer_events: policy_scope(Event)).rows
  end

  def family_needs_you(ward, forms, checklists)
    name = family_ward_name(ward)
    forms.count(&:to_do?) + checklists.reject { |checklist, _| checklist.ended? }.sum do |checklist, status|
      status.explained.count do |entry|
        entry.full? && MyGatherpackChecklistsHelper::UNFINISHED.include?(entry.status) && my_gatherpack_checklist_fix(checklist, entry, ward, ward: name)
      end
    end
  end

  def family_pooled_count?(entry)
    entry.full? && !entry.exempt? && entry.item.config["group_relationship_type_id"].present? && my_gatherpack_season_count(entry).present?
  end
end
