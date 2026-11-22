module MyGatherpack
  # Things one home page section already shows inside its own rows, so
  # another section leaves them out and each shows once. A checklist item
  # that lists a form, say, claims that form for its person: the forms
  # section then shows no row of its own for it.
  #
  #   MyGatherpack::Claims.register(:checklists, :form) { |subject| form ids }
  #   MyGatherpack::Claims.claimed?(view, :form, subject, form.id)
  #
  # Blocks run in the view context, so they can use the section's helpers.
  # Matching is by reference (ids), never by comparing what rows say.
  module Claims
    @claims = {}

    class << self
      # Registering the same key and kind again replaces it, so reloading
      # code is safe.
      def register(key, kind, &block)
        @claims[[ key, kind ]] = block
      end

      def unregister(key, kind)
        @claims.delete([ key, kind ])
      end

      # The ids of +kind+ that any section claims for +subject+.
      def ids(view, kind, subject)
        @claims.select { |(_, claimed), _| claimed == kind }.values
          .flat_map { |block| Array(view.instance_exec(subject, &block)) }.map(&:to_s).to_set
      end

      def claimed?(view, kind, subject, id)
        ids(view, kind, subject).include?(id.to_s)
      end
    end
  end
end
