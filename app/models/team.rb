class Team < ApplicationRecord
  has_neat_id :tm
  include CanBeHooked

  has_paper_trail versions: { class_name: "AuditLog" }
  belongs_to :team_type
  has_many :announcements
  has_many :badges
  has_many :events
  has_many :memberships, dependent: :destroy
  has_many :membership_applications, dependent: :destroy
  has_many :people, through: :memberships
  has_many :events
  has_many :pages
  has_many :time_clock_periods
  belongs_to :parent, class_name: "Team", optional: true
  has_many :children, class_name: "Team", foreign_key: :parent_id, dependent: :nullify
  has_many :calendar_notes, as: :noteable
  has_many :questions
  enum :join_permission, { added_by_admin: 0, added_by_manager: 1, added_by_current_member: 2, has_account: 3, requires_approval: 4 }

  validates :name, presence: true
  validates :join_permission, inclusion: { in: join_permissions.keys }
  validate :parent_not_below_itself, if: :parent_id_changed?

  scope :top_level, -> { where(parent_id: nil) }

  def self.ransackable_scopes(auth_object = nil)
    [ :top_level ]
  end

  def self.ransackable_attributes(auth_object = nil)
    [ "name", "team_type_id", "updated_at", "people.count", "parent_id", "join_permission" ]
  end

  def self.ransackable_associations(auth_object = nil)
    [ "team_type", "parent" ]
  end

  # Ids of the given teams and every team below them, in one recursive query.
  # UNION (not UNION ALL) drops rows already seen, so a cycle in parent_id
  # cannot loop forever.
  def self.subtree_ids(ids)
    ids = Array(ids).compact
    return [] if ids.empty?

    sql = sanitize_sql_array([ <<~SQL.squish, ids ])
      WITH RECURSIVE subtree(id) AS (
        SELECT teams.id FROM teams WHERE teams.id IN (?)
        UNION
        SELECT teams.id FROM teams INNER JOIN subtree ON teams.parent_id = subtree.id
      )
      SELECT id FROM subtree
    SQL
    connection.select_values(sql)
  end

  # Ids of the given teams and every team above them, in one recursive query.
  def self.ancestor_ids(ids)
    ids = Array(ids).compact
    return [] if ids.empty?

    sql = sanitize_sql_array([ <<~SQL.squish, ids ])
      WITH RECURSIVE ancestry(id, parent_id) AS (
        SELECT teams.id, teams.parent_id FROM teams WHERE teams.id IN (?)
        UNION
        SELECT teams.id, teams.parent_id FROM teams INNER JOIN ancestry ON teams.id = ancestry.parent_id
      )
      SELECT id FROM ancestry
    SQL
    connection.select_values(sql)
  end

  def siblings
    if parent
      Team.where(parent_id: parent_id).where.not(id: id)
    else
      []
    end
  end

  def all_descendant_ids
    self.class.subtree_ids(id) - [ id ]
  end

  def all_descendants
    children.flat_map { |child| [ child ] + child.all_descendants }
  end

  def all_ancestor_ids
    parent ? [ parent.id ] + parent.all_ancestor_ids : []
  end

  def all_ancestors
    parent ? [ parent ] + parent.all_ancestors : []
  end

  def ancestor_manager_ids
    Person.joins(:memberships)
      .where(memberships: { team_id: all_ancestor_ids, manager: true })
      .select("people.id")
  end

  def descendant_member_ids
    Person.joins(:memberships)
      .where(memberships: { team_id: all_descendant_ids + [ id ] })
      .select("people.id")
      .distinct
  end

  def all_people
    Person.joins(:memberships)
      .where(memberships: { team_id: all_descendant_ids + [ id ] })
      .or(Person.where(id: ancestor_manager_ids))
      .distinct
  end

  def descendant_people
    Person.joins(:memberships)
      .where(memberships: { team_id: all_descendant_ids + [ id ] })
      .distinct
  end

  def managers
    Person.joins(:memberships).where(memberships: { team_id: id, manager: true }).distinct
  end

  def all_managers
    ancestor_ids = [ id ] + all_ancestor_ids
    Person.joins(:memberships).joins(:user).where(memberships: { team_id: ancestor_ids, manager: true }).distinct
  end

  def all_managers_and_admins
    ancestor_ids = [ id ] + all_ancestor_ids
    Person.joins(:memberships).joins(:user).where(memberships: { team_id: ancestor_ids, manager: true }).or(Person.where(user: { admin: true })).distinct
  end

  def manager?(person)
    all_managers_and_admins.include?(person)
  end

  def identifier_icon
    "people-group"
  end

  private

  # A team under itself makes all_ancestors and all_descendants recurse
  # forever. Walk up from the new parent, remembering where we've been, so
  # the check itself stops even if the teams above already loop.
  def parent_not_below_itself
    seen = Set.new
    team = parent
    while team && seen.add?(team.id)
      if team.id == id
        errors.add(:parent_id, :not_below_itself, message: "can't be this team or one under it")
        return
      end
      team = team.parent
    end
  end
end
