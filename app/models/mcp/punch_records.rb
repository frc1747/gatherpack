# What the time clock tools share: a punch in list_punches' shape, the steps of
# TimeClockPunchesController's create and update, and reading a time argument.
module Mcp::PunchRecords
  SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      person: Mcp::Tool::REF_SCHEMA,
      period: { anyOf: [ Mcp::Tool::REF_SCHEMA, { type: "null" } ] },
      start_time: { type: "string" },
      end_time: { type: %w[string null] },
      hours: { type: %w[number null] },
      note: { type: %w[string null] },
      flags: { type: %w[array null], items: { type: "string" } }
    },
    required: %w[id person period start_time end_time hours note flags]
  }.freeze

  # Times the page takes in the app's time zone; an offset is honored. Four-digit
  # years only, and a time is required: a bare date isn't a clock time. Ruby would roll
  # an impossible date over and ignore an impossible offset, so neither gets through:
  # parse_time checks the date, and this the time and offset.
  TIME_FORMAT = /\A\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d(:[0-5]\d(\.\d+)?)?(Z|[+-](0\d|1[0-4]):?[0-5]\d)?\z/

  # What a form's single-line input can't send. It strips line breaks only, so a pasted
  # tab does get through.
  SINGLE_LINE_REFUSED = /[[:cntrl:]&&[^\t]]/

  private

  def punches_json(punches)
    flags = flags_by_punch(punches)
    punches.map { |punch| punch_json(punch, flags) }
  end

  # hours is null while the punch is open, as the page shows "-" (_time_clock_punch
  # line 7). The note appears only on the edit form, so it's returned only to those who
  # can open that (edit?). flags are the groups on the flagged page, as stored, and null
  # for those who can't open it (flagged?).
  def punch_json(punch, flags = flags_by_punch([ punch ]))
    period = punch.time_clock_period
    {
      id: punch.neat_id,
      person: person_json(punch.person),
      period: period && { id: period.neat_id, name: period.name.to_s },
      start_time: time_json(punch.start_time),
      end_time: time_json(punch.end_time),
      hours: punch.complete? ? hours_json(punch.hours) : nil,
      note: ctx.allowed?(punch, :edit?) ? punch.note : nil,
      flags: flags && flags.fetch(punch.id, [])
    }
  end

  # { punch id => its flags }, or nil if the viewer can't open the flagged page.
  def flags_by_punch(punches)
    return nil unless ctx.allowed?(TimeClockPunch, :flagged?)

    stored = TimeClockPunch.where(id: punches.map(&:id))
    flags = Hash.new { |hash, id| hash[id] = [] }
    stored.too_long.pluck(:id).each { |id| flags[id] << "too_long" }
    stored.still_clocked_in.pluck(:id).each { |id| flags[id] << "still_clocked_in" }
    stored.near_duplicates.pluck(:id).each { |id| flags[id] << "near_duplicate" }
    flags
  end

  # TimeClockPunchPolicy doesn't define create?, so the POST lets anyone record a punch
  # for anyone. The gate is the form's person list instead: "managed_people me"
  # (_form line 7). And a team's members may record for each other in an "added by team
  # member" period, as update? and the model's permission_check accept. A build whose
  # policy defines create? applies that too.
  def authorize_recording!(punch)
    ctx.authorize!(punch, :create?) if ctx.defines?(punch, :create?)
    raise Mcp::NotAllowed unless may_record_for?(punch)
  end

  def may_record_for?(punch)
    punch.person == ctx.person || ctx.person.can_manage(punch.person) || team_member_period?(punch.time_clock_period)
  end

  # Ending an open punch through MCP is for admins and managers only, by owner decision,
  # so a token can't stop someone's clock from anywhere. That covers giving it an end time,
  # deleting it, and handing it to someone else. Stricter than the page, which allows
  # these in some periods.
  def may_close_punches?
    ctx.user.admin || ctx.person.manager?
  end

  def team_member_period?(period)
    period&.team.present? && period.added_by_team_member? && ctx.person.all_teams.include?(period.team)
  end

  # The controller's save, with created_by set as it sets it (not stored: only the
  # model's permission_check reads it). That check refuses by name what the viewer's
  # role doesn't allow in this period.
  def save_punch!(punch)
    punch.created_by = ctx.person
    return if punch.save

    raise Mcp::NotAllowed, "Not allowed: #{punch.errors.full_messages_for(:time_clock_period).to_sentence}" if punch.errors.include?(:time_clock_period)

    invalid_argument!(punch.errors.full_messages.to_sentence)
  end

  def parse_time(value, name)
    raise ArgumentError unless value.match?(TIME_FORMAT)

    Date.iso8601(value[0, 10])
    Time.zone.iso8601(value)
  rescue ArgumentError
    invalid_argument!("#{name} must be a time like 2026-03-31T18:00:00")
  end

  def refuse_control_characters!(name, value)
    invalid_argument!("#{name} can't contain line breaks or control characters") if value&.match?(Mcp::PunchRecords::SINGLE_LINE_REFUSED)
  end
end
