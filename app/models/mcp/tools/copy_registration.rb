# Copies a registration as a new one, as the page's Copy and the save after it do
# (Intake::RegistrationsController#copy, line 33, then #create, line 41): copy? on the
# source (the team's managers and admins), Intake::Registration#copy for the lists and
# settings, and create? on the result. The page shows the copy as a form, with its dates
# moved on by the gap between the source's, "for a person to confirm", and the person saves
# it; so here the dates are given (opens_at required) and nothing is guessed. closes_at
# defaults to the source's length from opens_at, or none when the source has no end.
#
# What the page's save keeps (registration_params, create): team lists only for teams the
# viewer manages, badges only those they may give (the helpers' rules), the checklist only
# when they run it (RegistrationChecklistParams) and only while the checklists feature is on (with
# it off the form has neither field, so the copy has no checklist and no gate), and no successor. The slug is a new random
# one. A copy that comes out invalid on the page (with checklists on, a gate with no checklist left; no team
# to apply to) is refused here with the page's message. Created by the caller's person.
class Mcp::Tools::CopyRegistration < Mcp::Tool
  include Mcp::IntakeRecords

  tool_name "copy_registration"
  description "Copy a registration, as Copy does on its page, with the dates you give: opens_at, and closes_at (default: the same length as the original, or none). " \
    "Only the teams you manage, the badges you may give and a checklist you run carry over. Returns the new registration."
  scope :write
  feature :intake
  input_schema(
    properties: {
      registration_id: { type: "string", description: "The registration to copy (ireg_)" },
      opens_at: { type: "string", description: "When the copy opens, ISO 8601 date-time" },
      closes_at: { type: "string", description: "When it closes, ISO 8601 date-time after opens_at. Default: the original's length, or no end." },
      title: { type: "string", description: "Its title (default: the original's)" }
    },
    required: %w[registration_id opens_at]
  )
  output_schema(Mcp::IntakeRecords::SCHEMA)

  def call(registration_id:, opens_at:, closes_at: nil, title: nil)
    source = ctx.find(Intake::Registration, registration_id)
    ctx.authorize!(source, :copy?)

    copy = source.copy
    copy.title = title if title.present?
    copy.opens_at = parse_time(opens_at, "opens_at")
    copy.closes_at = closes_at ? parse_time(closes_at, "closes_at") : source.closes_at && copy.opens_at + (source.closes_at - source.opens_at)
    copy.created_by = ctx.person
    keep_what_the_caller_may(copy)
    ctx.authorize!(copy, :create?)
    copy.save!

    changed!(copy)
    registration_json(copy)
  rescue ActiveRecord::RecordInvalid => e
    invalid_argument!(e.record.errors.full_messages.to_sentence)
  end

  private

  def keep_what_the_caller_may(copy)
    manageable = (ctx.user.admin ? Team.all : ctx.person.all_managed_teams).pluck(:id)
    Intake::RegistrationTeam.kinds.each_key do |kind|
      copy.public_send(:"#{kind}_team_ids=", copy.public_send(:"#{kind}_team_ids") & manageable)
    end
    copy.badge_ids = copy.badges.select { |badge| ctx.allowed?(badge, :update?) }.map(&:id)
    copy.checklist_id = nil unless Checklists.enabled? && runs_checklist?(copy.checklist_id)
    copy.gate_approval = false unless Checklists.enabled?
  end

  def runs_checklist?(checklist_id)
    checklist_id && ctx.policy_scope(Checklist).where(status: :active).find_by(id: checklist_id)&.organizer?(ctx.person)
  end
end
