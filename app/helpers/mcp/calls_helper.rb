module Mcp::CallsHelper
  # Types with a page of their own at one ID. A membership's page also needs its team,
  # and a token, which a tool can remove, is linked only while it exists (see below). Others (a badge assignment, a login) aren't linked: a login is reached
  # from its person, listed in the same row.
  CHANGED_RECORD_PATHS = {
    "Person" => :person_path,
    "Team" => :team_path,
    "Badge" => :badge_path,
    "Event" => :event_path
  }.freeze

  # Types whose current name is shown in place of the ID. changed_records keeps only
  # type and ID (it's the audit record), so the name is read when the page renders.
  NAMED_RECORDS = { "Person" => [ Person, :display_name ], "Team" => [ Team, :name ], "Badge" => [ Badge, :name ] }.freeze

  # A link to a { "type", "id" } entry of McpToolCall#changed_list, or its text
  # where it has no page. Some routes exist only while their feature is on. A
  # person, team or badge shows its current name; one that's gone shows its ID and
  # "(no longer exists)", with no link.
  def changed_record_link(record)
    label = changed_record_label(record)
    path = changed_record_path(record)
    path ? link_to(label, path, data: { turbo_frame: "_top" }) : label
  end

  private

  def changed_record_label(record)
    default = "#{record["type"]} #{record["id"]}"
    return default unless NAMED_RECORDS.key?(record["type"])

    names = changed_names(record["type"])
    return "#{default} (no longer exists)" unless names.key?(record["id"])

    "#{record["type"]} #{names[record["id"]].presence || record["id"]}"
  end

  def changed_record_path(record)
    return if NAMED_RECORDS.key?(record["type"]) && !changed_names(record["type"]).key?(record["id"])

    changed_record_target(record)
  end

  # { id => current name } for every record of a type on the page, in one query.
  def changed_names(type)
    @changed_names ||= {}
    @changed_names[type] ||= begin
      klass, attribute = NAMED_RECORDS.fetch(type)
      ids = (@calls || []).flat_map { |call| call.changed_list.select { |r| r["type"] == type }.map { |r| r["id"] } }.uniq
      klass.where(id: ids).pluck(:id, attribute).to_h
    end
  end

  def changed_record_target(record)
    return changed_membership_path(record["id"]) if record["type"] == "Membership"
    return changed_token_path(record["id"]) if record["type"] == "Token"

    helper = CHANGED_RECORD_PATHS[record["type"]]
    public_send(helper, record["id"]) if helper && respond_to?(helper)
  end

  # changed_records holds only type and id, so this looks the team up. Nil once the
  # membership has been removed.
  def changed_membership_path(id)
    team_id = Membership.where(id: id).pick(:team_id)
    team_membership_path(team_id, id) if team_id
  end

  # Nil once the token has been removed, or while its feature is off.
  def changed_token_path(id)
    token_path(id) if respond_to?(:token_path) && Token.exists?(id: id)
  end
end
