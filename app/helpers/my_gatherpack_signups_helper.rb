module MyGatherpackSignupsHelper
  # The viewer's upcoming sign-ups as home-page rows. They come from
  # SignupsSummary, so the same sign-ups, on the same sheets, as the
  # dashboard card, and each note is worded by SignupsSummariesHelper as it
  # is there. A row names a person only when it isn't the viewer's own: the
  # ward when it's theirs, otherwise whoever the viewer signed up.
  def my_gatherpack_signup_items
    summary = SignupsSummary.new(current_user, limit: MyGatherpackHelper::MY_GATHERPACK_ROW_LIMITS[:coming_up])
    viewer = summary.person
    wards = viewer.respond_to?(:wards) ? viewer.wards.to_a : []

    summary.signups.map do |signup|
      subject = signup.on_behalf_of || signup.person
      ward = [ subject, signup.person ].find { |person| wards.include?(person) }
      for_other = signup.person_id != viewer.id && signup.signed_up_by_id == viewer.id
      note = for_other ? signups_summary_for_other(signup, viewer) : signups_summary_for(signup, viewer)
      who = signup.person.identifier_name if for_other && ward.nil?

      MyGatherpack::Item.new(
        title: signup.signup_position.name,
        detail: [ my_gatherpack_signup_time(signup.event), signup.signup_sheet.title, who, note ].compact_blank.join(" · "),
        at: signup.event.start_time,
        path: signup_sheet_path(signup.signup_sheet),
        ward: ward&.first_name.presence || ward&.identifier_name
      )
    end
  end

  private

  def my_gatherpack_signup_time(event)
    return "Time not set yet" if SignupNotices.time_unset?(event.start_time, event.end_time)

    event.start_time.strftime("%-I:%M %p")
  end
end
