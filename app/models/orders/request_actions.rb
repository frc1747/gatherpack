# The requester's and buyer's actions on a whole request (spec §3.2–3.4,
# §3.10). Each takes the request's row lock and writes its timeline entry
# in the same transaction. Who may call them is the policies' business;
# what the request's state allows is checked here and refused with
# Orders::Refused.
module Orders
  module RequestActions
    extend ActiveSupport::Concern

    # A change to any of these on a line voids standing approvals: what the
    # item is (for a line with no link the description is the part), where
    # it comes from, and how it's counted.
    MATERIAL_LINE_FIELDS = %w[
      description vendor_id other_vendor_name vendor_part_number manufacturer manufacturer_part_number url unit units_per
    ].freeze

    # Request fields that can't change once it's approved: they would move
    # the total or who approves it after the decision.
    FIXED_AFTER_APPROVAL = %w[team_id estimated_shipping_cents].freeze

    # Request fields the edit action records.
    EDITABLE_FIELDS = %w[title purpose needed_by team_id funding_source_id estimated_shipping_cents].freeze

    def submit!(by:)
      locked do
        raise Orders::Refused, "Only a draft can be submitted." unless draft?
        lines = live_lines
        raise Orders::Refused, "Add at least one item." if lines.empty?

        lines.each(&:validate!)
        self.title = lines.first.display_name if title.blank?
        update!(status: :submitted, submitted_at: Time.current)
        log!(:submitted, by: by, changes: { "status" => %w[draft submitted] })
      end
    end

    # Sends a request back to its approvers after they asked for changes.
    # Approvals stand unless a material change has cleared them since.
    def resubmit!(by:, comment: nil)
      locked do
        raise Orders::Refused, "Only a request that needs changes can be resubmitted." unless changes_requested?
        raise Orders::Refused, "Add at least one item." if live_lines.empty?

        update!(status: :submitted, submitted_at: Time.current)
        log!(:submitted, by: by, changes: { "status" => %w[changes_requested submitted] }, comment: comment)
      end
    end

    # Changes the request's own fields (EDITABLE_FIELDS). Before approval,
    # moving it to another team, or raising the total past the tolerance,
    # voids standing approvals. Once approved, the team and estimated
    # shipping are fixed. Only someone who may set them changes the funding
    # source and estimated shipping (see Orders::Access#sets_funding? and
    # #sees_estimated_shipping?).
    def edit!(attributes, by:)
      locked do
        raise Orders::Refused, "This request can't be changed any more." if finished?

        before_total = total_cents
        assign_attributes(attributes.to_h.stringify_keys.slice(*EDITABLE_FIELDS))
        changed = changes.keys & EDITABLE_FIELDS
        access = Orders::Access.for(by)
        if changed.include?("funding_source_id") && !access.sets_funding?(self)
          raise Orders::Refused, "You can't choose the funding source for this request."
        end
        if changed.include?("estimated_shipping_cents") && !access.sees_estimated_shipping?(self)
          raise Orders::Refused, "You can't change the estimated shipping."
        end
        if (changed & FIXED_AFTER_APPROVAL).any? && !editable?
          raise Orders::Refused, "The team and estimated shipping can't change once the request is approved."
        end

        line_sources = changed.include?("team_id") ? drop_funding_unusable_by_team : {}
        recorded = changes_to_record
        recorded["line_funding_source_ids"] = line_sources if line_sources.any?
        save!
        next if recorded.empty? || draft?

        cleared = editable? && clear_approvals_if_material(changed.include?("team_id"), before_total)
        log!(:edited, by: by, changes: recorded.merge(cleared ? { "approvals_cleared" => true } : {}))
      end
    end

    # Adds a line. Outside a draft that's a material change.
    def add_line!(attributes, by:)
      locked do
        raise Orders::Refused, "Items can't be added to this request now." unless editable?

        line = order_lines.create!(attributes.to_h.symbolize_keys.merge(position: (order_lines.maximum(:position) || -1) + 1))
        unless draft?
          cleared = clear_approvals_if_material(true, nil)
          log!(:edited, by: by, line: line, changes: { "added" => line.display_name }.merge(cleared ? { "approvals_cleared" => true } : {}))
        end
        line
      end
    end

    # Changes a line before approval, by the requester or an approver.
    # Changing its vendor or part, or raising the total past the tolerance,
    # voids standing approvals; lowering a quantity doesn't.
    def edit_line!(line, attributes, by:)
      locked do
        raise Orders::Refused, "Items can't be changed on this request now." unless editable?

        line = order_lines.find(line.id)
        before_total = total_cents
        line.assign_attributes(attributes.to_h.stringify_keys.slice(*OrderLine::EDITABLE_FIELDS))
        changes = line.changes_to_record
        line.save!
        next line if changes.empty? || draft?

        order_lines.reset
        cleared = clear_approvals_if_material((changes.keys & MATERIAL_LINE_FIELDS).any?, before_total)
        log!(:edited, by: by, line: line, changes: changes.merge(cleared ? { "approvals_cleared" => true } : {}))
        line
      end
    end

    # Takes a line off a request that isn't approved yet: a draft's line is
    # deleted, others are cancelled (which isn't a material change).
    def remove_line!(line, by:, reason: nil)
      locked do
        raise Orders::Refused, "Items can't be removed from this request now." unless editable?

        line = order_lines.find(line.id)
        if draft?
          line.destroy!
        else
          line.update!(status: :cancelled)
          log!(:cancelled, by: by, line: line, comment: reason)
        end
      end
    end

    # Allowed until anything is on a purchase.
    def cancel!(by:, reason: nil)
      locked do
        unless status.in?(%w[draft submitted changes_requested approved]) && order_lines.none?(&:purchase_id)
          raise Orders::Refused, "This request can't be cancelled once something is ordered."
        end

        from = status
        order_lines.each { |line| line.update!(status: :cancelled) unless line.cancelled? }
        update!(status: :cancelled)
        log!(:cancelled, by: by, changes: { "status" => [ from, "cancelled" ] }, comment: reason) unless from == "draft"
      end
    end

    # Closes a received request, by hand or (by: nil) after
    # orders_close_after_days.
    def close!(by: nil, comment: nil)
      locked do
        raise Orders::Refused, "Only a received request can be closed." unless received?

        update!(status: :closed, closed_at: Time.current)
        log!(:closed, by: by, changes: { "status" => %w[received closed] }, comment: comment)
      end
    end

    # Deletes a draft. Only a draft can go; anything else is cancelled, so
    # its timeline stays.
    def discard_draft!(by:)
      locked do
        raise Orders::Refused, "Only a draft can be deleted. Cancel the request instead." unless draft?
        raise Orders::Refused, "This draft has a timeline, so cancel it instead." if events.exists?

        destroy!
      end
    end

    # Comments are for a request others can see, so not for a draft.
    def comment!(text, by:)
      raise Orders::Refused, "Write a comment first." if text.blank?
      raise Orders::Refused, "Comments can be added once the request is sent." if draft?

      locked { log!(:commented, by: by, comment: text) }
    end

    def follow!(person)
      locked do
        next if watched_by?(person)

        order_request_watchers.create!(person: person)
        log!(:followed, by: person) unless draft?
      end
    end

    def unfollow!(person)
      locked do
        watcher = order_request_watchers.find_by(person_id: person.id)
        next if watcher.nil?

        watcher.destroy!
        log!(:unfollowed, by: person) unless draft?
      end
    end

    # A new draft for the person with this request's lines (at their last
    # known price) and its team, title and purpose.
    def order_again(by:, team: self.team)
      lines = live_lines.map(&:reorder_attributes)
      OrderRequest.draft_for(person: by, team: team, lines: lines, title: title, purpose: purpose)
    end

    # A new draft for the person with a copy of this request and its lines:
    # same team and funding source, the lines' own fields as the requester
    # filled them in. Approvals, followers, purchases, receipts and the
    # timeline stay behind.
    def duplicate(by:)
      transaction do
        copy = OrderRequest.create!(
          requested_by: by, team: team, funding_source: funding_source, status: :draft,
          title: "#{display_title} (copy)", purpose: purpose, needed_by: needed_by,
          estimated_shipping_cents: estimated_shipping_cents
        )
        order_lines.each do |line|
          copy.order_lines.create!(line.attributes.slice(*OrderLine::EDITABLE_FIELDS, "position", "funding_source_id"))
        end
        copy
      end
    end

    # Records every open line on the request (or, with purchase:, only that
    # purchase's lines) as fully received. A line with a problem is left for
    # its own Receive and the buyer.
    def mark_all_received!(by:, purchase: nil, received_on: Date.current)
      locked do
        lines = order_lines.select { |line| line.open_to_receive? && !line.problem? }
        lines = lines.select { |line| line.purchase_id == purchase.id } if purchase
        raise Orders::Refused, "Nothing here is waiting to be received." if lines.empty?

        lines.each do |line|
          line.record_delivery!(by: by, quantity: line.to_come_quantity, received_on: received_on)
        end
      end
    end

    # Moves an approved request between approved, ordering and received to
    # match its lines. Called by the line actions, inside the lock.
    def refresh_status_from_lines
      return unless approved? || ordering? || received?

      lines = order_lines.reload.reject(&:cancelled?)
      status_now =
        if lines.empty? then :cancelled
        elsif lines.all?(&:received?) then :received
        elsif lines.any? { |line| line.purchase_id.present? || line.received? } then :ordering
        else :approved
        end
      update!(status: status_now) unless status == status_now.to_s
    end

    # After a buyer's change raises the total past the tolerance over the
    # approved total, the lines whose cost this change raised need approving
    # again by the final step. Within it, or when none of lines rose,
    # nothing waits. Returns whether re-approval is needed.
    def check_price_tolerance(lines, by:)
      return false if approved_total_cents.nil?

      raised = lines.select { |line| line.cost_rose? && !line.cancelled? }
      return false if raised.empty?

      rise = total_cents - approved_total_cents
      return false if rise <= Orders::Config.price_tolerance.allowance_cents(approved_total_cents)

      raised.each { |line| line.update!(status: :needs_reapproval) }
      log!(:reapproval_needed, by: by, changes: {
        "total" => [ Money.new(approved_total_cents).format, total.format ],
        "lines" => raised.map(&:display_name)
      })
      true
    end

    # After a move to another team, clears the request's funding source and
    # any line's own source the new team can't use (they're for another
    # team's budget or gift). Returns the lines' cleared sources as
    # { line id => [before, nil] }; the request's shows in its own changes.
    def drop_funding_unusable_by_team
      self.funding_source = nil if funding_source && !funding_source.usable_by?(team)
      order_lines.reject(&:cancelled?).each_with_object({}) do |line, cleared|
        next if line.funding_source.nil? || line.funding_source.usable_by?(team)

        cleared[line.id] = [ line.funding_source_id, nil ]
        line.update!(funding_source: nil)
      end
    end

    # The request fields changed in memory, as name => [before, after].
    def changes_to_record
      changes.slice(*EDITABLE_FIELDS).transform_values { |pair| pair.map { |value| value.is_a?(Date) ? value.iso8601 : value } }
    end

    private

    # Voids standing approvals when the change is material: a new line, a
    # changed vendor or part, or a total raised past the tolerance over the
    # total last approved. Returns whether any were cleared.
    def clear_approvals_if_material(material, before_total)
      standing = order_approvals.reload.select { |approval| approval.cleared_at.nil? && approval.approved? }
      return false if standing.empty?

      unless material
        base = approved_total_cents || before_total
        return false if base.nil? || total_cents - base <= Orders::Config.price_tolerance.allowance_cents(base)
      end

      now = Time.current
      standing.each { |approval| approval.update!(cleared_at: now) }
      order_approvals.reset
      true
    end
  end
end
