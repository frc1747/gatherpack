module SignupsSummariesHelper
  # Who a summarized sign-up is for, from the viewer's side: "For Kid World",
  # "Taken for you by Organizer World", or nil for the viewer's own.
  def signups_summary_for(signup, viewer)
    if signup.person_id != viewer.id && signup.on_behalf_of_id == viewer.id
      "Taken for you by #{signup.person.identifier_name}"
    elsif signup.on_behalf_of_id != viewer.id
      "For #{signup.on_behalf_of.identifier_name}"
    elsif signup.person_id != viewer.id
      "For #{signup.person.identifier_name}"
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
