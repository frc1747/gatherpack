# The New request and Edit request form (spec §3.16), applied to a request
# through its domain actions: OrderRequest.draft_for for a new one, then
# #edit!, #add_line!, #edit_line! and #remove_line!. Nothing here changes a
# request any other way, so the timeline and approvals follow as they do
# for every other change.
#
# params are the permitted order_request params: the request's own fields
# and lines, a hash of item fields keyed by a number the form chose. An
# item's store comes as vendor_choice: a vendor id, "other" (with
# other_vendor_name) or "not_sure". Its price comes in currency units as
# estimated_unit_price.
module Orders
  class RequestForm
    REQUEST_FIELDS = %w[purpose needed_by team_id funding_source_id].freeze
    LINE_FIELDS = %w[
      description url quantity other_vendor_reason vendor_part_number manufacturer manufacturer_part_number
      unit units_per note
    ].freeze
    # Fields that make an item worth saving; a new item with none of them is
    # an empty form the requester hasn't touched.
    CONTENT_FIELDS = %w[
      description url other_vendor_name vendor_part_number manufacturer manufacturer_part_number
      unit units_per estimated_unit_price note
    ].freeze

    # One item on the form: its key, the line it edits (new or saved) and
    # whether the requester removed it.
    Entry = Struct.new(:key, :line, :attributes, :photo, :remove, keyword_init: true)

    attr_reader :order_request, :errors, :entries, :line_ids, :removed_keys

    def initialize(order_request, by:, params:)
      @order_request = order_request
      @by = by
      @params = params.to_h.deep_stringify_keys
      @errors = []
      @line_ids = {}
      @removed_keys = []
    end

    # Saves the form, all or nothing. Returns false with #errors set when a
    # field or the request's state doesn't allow it.
    def save
      @entries = build_entries
      check_entries
      return false if errors.any?

      OrderRequest.transaction do
        order_request.new_record? ? create_draft : apply_changes
      end
      true
    rescue Orders::Refused => e
      errors << e.message
      false
    rescue ActiveRecord::RecordInvalid => e
      errors.concat(e.record.errors.full_messages)
      false
    end

    # A new request with nothing filled in yet, which autosave doesn't keep.
    def blank?
      @entries ||= build_entries
      order_request.new_record? && entries.none? && @params["purpose"].blank?
    end

    # The items to show again when saving failed: the requester's values,
    # with removed ones kept (hidden) so the next save removes them.
    def display_lines
      (@entries || build_entries).map { |entry| [ entry.key, entry.line, entry.remove ] }
    end

    private

    def create_draft
      attributes = request_attributes
      team = Team.find_by(id: attributes.delete("team_id")) || order_request.team
      funding_source_id = attributes.delete("funding_source_id")
      lines = entries.reject(&:remove).map { |entry| entry.attributes.merge(photo_attributes(entry)) }

      draft = OrderRequest.draft_for(person: @by, team: team, lines: lines, **attributes.symbolize_keys)
      draft.order_lines.reload.zip(entries.reject(&:remove)) { |line, entry| line_ids[entry.key] = line.id }
      draft.edit!({ "funding_source_id" => funding_source_id }, by: @by) if funding_source_id.present?
      @order_request = draft
    end

    def apply_changes
      attributes = request_attributes
      order_request.edit!(attributes, by: @by) if attributes.any?

      entries.each do |entry|
        if entry.remove
          order_request.remove_line!(entry.line, by: @by) if entry.line.persisted?
          removed_keys << entry.key
        elsif entry.line.persisted?
          line = order_request.edit_line!(entry.line, entry.attributes, by: @by)
          attach_photo(line, entry.photo) if entry.photo
          line_ids[entry.key] = line.id
        else
          line = order_request.add_line!(entry.attributes.merge(photo_attributes(entry)), by: @by)
          line_ids[entry.key] = line.id
        end
      end
    end

    # A new photo on a saved item. Outside a draft it's in the timeline.
    def attach_photo(line, photo)
      order_request.locked do
        line.photo.attach(photo)
        order_request.log!(:edited, by: @by, line: line, changes: { "photo" => [ nil, "added" ] }) unless order_request.draft?
      end
    end

    def photo_attributes(entry)
      entry.photo ? { "photo" => entry.photo } : {}
    end

    def request_attributes
      attributes = @params.slice(*REQUEST_FIELDS).transform_values { |value| value.to_s.strip.presence }
      attributes.delete("team_id") if attributes["team_id"].nil?
      attributes
    end

    def build_entries
      lines_params = @params["lines"] || {}
      lines_params.sort_by { |key, _| key.to_i }.filter_map do |key, values|
        values = values.to_h.stringify_keys
        remove = ActiveModel::Type::Boolean.new.cast(values["_destroy"])
        photo = values["photo"].presence if values["photo"].respond_to?(:original_filename)
        next if values["id"].blank? && (remove || (photo.nil? && values.slice(*CONTENT_FIELDS).values.all?(&:blank?)))

        line = values["id"].present? ? order_request.order_lines.find(values["id"]) : OrderLine.new
        Entry.new(key: key.to_s, line: line, attributes: line_attributes(values), photo: photo, remove: remove)
      end
    end

    # Checks each item before anything is saved, so an error names its item.
    def check_entries
      entries.reject(&:remove).each_with_index do |entry, index|
        if entry.attributes.key?("estimated_unit_price_cents") && entry.attributes["estimated_unit_price_cents"] == :invalid
          errors << "Item #{index + 1}: the price isn't a number"
          entry.attributes.delete("estimated_unit_price_cents")
        end
        entry.line.assign_attributes(entry.attributes)
        entry.line.valid?
        # A new item joins its request when it's saved.
        entry.line.errors.delete(:order_request) if entry.line.new_record?
        next if entry.line.errors.empty?

        entry.line.errors.full_messages.each { |message| errors << "Item #{index + 1}: #{message}" }
      end
    end

    def line_attributes(values)
      attributes = values.slice(*LINE_FIELDS).transform_values { |value| value.to_s.strip.presence }
      attributes["quantity"] ||= 1 if values.key?("quantity")
      attributes.merge!(vendor_attributes(values)) if values.key?("vendor_choice")
      attributes["estimated_unit_price_cents"] = price_cents(values["estimated_unit_price"]) if values.key?("estimated_unit_price")
      attributes
    end

    def vendor_attributes(values)
      case values["vendor_choice"].to_s
      when "other"
        { "vendor_id" => nil, "other_vendor_name" => values["other_vendor_name"].to_s.strip.presence }
      when "", "not_sure"
        { "vendor_id" => nil, "other_vendor_name" => nil }
      else
        { "vendor_id" => Vendor.find_by(id: values["vendor_choice"])&.id, "other_vendor_name" => nil }
      end
    end

    # "12.50", "$1,200" → cents; blank → nil; anything else → :invalid.
    def price_cents(text)
      text = text.to_s.strip.delete("$,")
      return nil if text.empty?
      return :invalid unless text.match?(/\A\d+(\.\d{0,2})?\z/)

      (text.to_d * 100).round
    end
  end
end
