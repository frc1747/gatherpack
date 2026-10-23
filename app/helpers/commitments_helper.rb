module CommitmentsHelper
  # "2 confirmed, 1 planned, 3 owed shifts"
  def commitment_summary(progress)
    unit = progress.commitment.unit
    "#{progress.confirmed} confirmed, #{progress.planned} planned, #{progress.owed} #{unit} owed"
  end

  # A source line's credit, with progress toward the next credit
  # ("1 confirmed, 1 planned · 2 of 3 toward 1").
  def commitment_line_summary(line)
    parts = [ "#{line.confirmed_credits} confirmed" ]
    parts << "#{line.planned_credits} planned" if line.planned_credits.positive?
    text = parts.join(", ")
    text += " · #{line.partial} of #{line.source.per} toward #{line.source.credits}" if line.partial.positive?
    text += " · cap of #{line.source.max_credits} reached" if line.capped
    text
  end

  def commitment_status_badge(progress)
    if progress.met?
      tag.span("Met", class: "badge text-bg-success")
    elsif progress.planned.positive?
      tag.span("In progress", class: "badge text-bg-info")
    else
      tag.span("Open", class: "badge text-bg-secondary")
    end
  end

  def commitment_period(commitment)
    "#{commitment.starts_on.strftime("%b %-d, %Y")} – #{commitment.ends_on.strftime("%b %-d, %Y")}"
  end
end
