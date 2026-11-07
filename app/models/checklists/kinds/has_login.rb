module Checklists
  module Kinds
    # Has a login with an email.
    class HasLogin < ItemKind
      class << self
        def label = "Has a login"
        def description = "Can sign in"
        def describe(_item) = "Has a login with an email"

        def invalidations
          [ [ ::Person, ->(person) { [ person.id ] } ], [ ::User, ->(user) { ::Person.where(user_id: user.id).ids } ] ]
        end
      end

      def evaluate(person_ids)
        with_login = ::Person.joins(:user).where(id: person_ids, users: { created_at: ..window.end_time })
          .where.not(users: { email: [ nil, "" ] }).ids.to_set

        person_ids.index_with do |person_id|
          if with_login.include?(person_id)
            Result.met("Has a login", detail: "Has a login with an email")
          else
            Result.not_met("No login", detail: "No login with an email yet", fix: { "label" => "Ask a leader to invite you" })
          end
        end
      end
    end
  end
end
