module SignupsSummariesHelper
  # Who takes a summarized sign-up and whose it counts as, from the viewer's
  # side, by the rules of the sheet's My sign-ups (signup_sheets/_member_signups):
  # "Taken for you by Organizer World", "on behalf of Kid World" (the viewer
  # takes it), or nil for the viewer's own.
  def signups_summary_for(signup, viewer)
    parts = []
    if signup.person_id != viewer.id && signup.on_behalf_of_id == viewer.id
      parts << "Taken for you by #{signup.person.identifier_name}"
    end
    if signup.on_behalf_of_id != signup.person_id && signup.on_behalf_of_id != viewer.id
      parts << "on behalf of #{signup.on_behalf_of.identifier_name}"
    end
    parts.join(" ").presence
  end

  # The note under a place the viewer signed someone else up for, which the
  # taker's name leads: "On your behalf", "on behalf of Kid World", or nil.
  def signups_summary_for_other(signup, viewer)
    if signup.on_behalf_of_id == viewer.id
      "On your behalf"
    elsif signup.on_behalf_of_id != signup.person_id
      "on behalf of #{signup.on_behalf_of.identifier_name}"
    end
  end

  # "You owe 2 more shifts", "Kid World owes 1 more shift",
  # "You and Kid World are done (2 shifts)".
  def signups_summary_owed(progress, viewer)
    members = progress.members
    others = members.reject { |member| member.id == viewer.id }.map(&:display_name)
    you = others.size < members.size
    who = you ? [ "You", *others ].to_sentence : others.to_sentence
    plural = you || others.size > 1
    unit = progress.commitment.unit

    if progress.met?
      "#{who} #{plural ? "are" : "is"} done (#{progress.owed} #{progress.owed == 1 ? unit.singularize : unit})"
    else
      "#{who} #{plural ? "owe" : "owes"} #{progress.remaining} more #{progress.remaining == 1 ? unit.singularize : unit}"
    end
  end
end
