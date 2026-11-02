# What the sign-up read tools share: how a slot's places are counted and how
# an event, position and sign-up are returned. Included by the tools; it
# makes no permission decisions, each tool decides what the viewer may see
# before it formats anything.
module Mcp::Tools::SignupFormat
  EVENT_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      start_time: { type: "string" },
      end_time: { type: %w[string null] },
      location: { type: %w[string null] }
    },
    required: %w[id name start_time end_time location]
  }.freeze

  POSITION_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      name: { type: "string" },
      kind: { type: "string", enum: %w[people items] },
      description: { type: %w[string null] },
      unit: { type: %w[string null] }
    },
    required: %w[id name kind description unit]
  }.freeze

  SHEET_REF_SCHEMA = {
    type: "object",
    properties: { id: { type: "string" }, title: { type: "string" } },
    required: %w[id title]
  }.freeze

  # A sign-up as the page shows it. on_behalf_of and note are added by the
  # tool only for those who may see them.
  SIGNUP_SCHEMA = {
    type: "object",
    properties: {
      id: { type: "string" },
      status: { type: "string", enum: %w[active cancelled fulfilled no_show] },
      person: Mcp::Tool::REF_SCHEMA,
      on_behalf_of: Mcp::Tool::REF_SCHEMA,
      answer: { type: %w[string null] },
      quantity: { type: %w[integer null] },
      note: { type: %w[string null] }
    },
    required: %w[id status person answer quantity]
  }.freeze

  private

  def event_json(event)
    { id: event.neat_id, name: event.name, start_time: time_json(event.start_time), end_time: time_json(event.end_time),
      location: event.location.presence }
  end

  def position_json(position)
    { id: position.neat_id, name: position.name, kind: position.kind, description: position.description.presence,
      unit: (position.unit.presence if position.items?) }
  end

  # Quantity is only set for item sign-ups, as the page shows it.
  def signup_json(signup)
    { id: signup.neat_id, status: signup.status, person: person_json(signup.person), answer: signup.answer.presence,
      quantity: (signup.quantity if signup.signup_position.items?) }
  end

  # Places or units taken by active and fulfilled sign-ups, from the loaded
  # records, as the page counts them.
  def slot_used(slot)
    slot.signups.select { |signup| signup.active? || signup.fulfilled? }.sum(&:usage)
  end

  # Places or units still open, or nil when the slot has no cap.
  def slot_open(slot)
    cap = slot.capacity_value
    cap && [ cap - slot_used(slot), 0 ].max
  end
end
