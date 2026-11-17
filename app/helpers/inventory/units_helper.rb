# Words and small pieces for the unit and machine pages (inventory spec
# §3.15). Conditions, place types and reading types are managed lists:
# names come from their rows, colours from the condition's flags.
module Inventory
  module UnitsHelper
    UNIT_ACTION_LABELS = {
      "install" => "Install", "take_off" => "Take off", "move" => "Move", "check" => "Check",
      "mark_for_repair" => "Mark for repair", "repaired" => "Repaired", "retire" => "Retire"
    }.freeze
    UNIT_ACTION_ICONS = {
      "install" => "screwdriver-wrench", "take_off" => "arrow-up-from-bracket", "move" => "right-left",
      "check" => "clipboard-check", "mark_for_repair" => "triangle-exclamation", "repaired" => "wrench",
      "retire" => "box-archive"
    }.freeze
    # History words, for every event action.
    UNIT_EVENT_WORDS = UNIT_ACTION_LABELS.merge(
      "take_off" => "Taken off", "move" => "Moved", "install" => "Installed", "check" => "Checked",
      "mark_for_repair" => "Marked for repair", "retire" => "Retired", "received" => "Received",
      "tracked" => "Started tracking"
    ).freeze
    # A condition's badge colour: by flag, and Worn (by key) amber.
    def unit_condition_class(condition)
      if condition.nil? then "text-bg-light"
      elsif condition.needs_attention? then "text-bg-danger"
      elsif condition.out_of_service? then "text-bg-secondary"
      elsif condition.key == "worn" then "text-bg-warning"
      else "text-bg-success"
      end
    end

    # A unit's (or a UnitCondition's) condition as a badge.
    def unit_condition_badge(condition)
      condition = condition.unit_condition if condition.is_a?(ItemUnit)
      tag.span(condition&.name || "No condition", class: "badge #{unit_condition_class(condition)}")
    end

    def unit_action_label(action)
      UNIT_ACTION_LABELS.fetch(action.to_s)
    end

    # The actions that fit the unit's state and that the viewer may take,
    # in the order the unit page shows them.
    def unit_actions_for(unit)
      return [] if unit.out_of_service? || !unit.active?

      actions = %w[install]
      actions << (unit.installed? ? "take_off" : "move")
      actions << "check"
      actions << (unit.flagged? ? "repaired" : "mark_for_repair")
      actions << "retire" unless unit.installed?
      actions.select { |action| policy(unit).public_send(:"#{action}?") }
    end

    def unit_action_button(unit, action)
      link_to inventory_unit_action_form_path(unit, act: action),
        class: "btn btn-lg #{%w[mark_for_repair retire].include?(action) ? "btn-danger" : "btn-primary"} text-start" do
        icon_text(UNIT_ACTION_ICONS.fetch(action), unit_action_label(action))
      end
    end

    # Where the unit is: "Rover, in Left module" or "Shop › Cabinet › Bin 1".
    def unit_whereabouts(unit)
      place = unit.location.machine? ? unit.location.name : unit.location.full_name
      return place if unit.installed_in.nil?

      safe_join([ place, ", in ", link_to(unit.installed_in.identifier_name, inventory_unit_path(unit.installed_in)) ])
    end

    # Storage places to pick from, as [full name, id], by full name.
    def inventory_place_options(locations)
      names = inventory_full_names(locations)
      locations.map { |location| [ names[location.id], location.id ] }.sort_by(&:first)
    end

    # Full names for many places from one query, instead of a walk each.
    def inventory_full_names(locations)
      parents = Location.pluck(:id, :parent_id, :name).to_h { |id, parent_id, name| [ id, [ parent_id, name ] ] }
      locations.to_h do |location|
        path = []
        id = location.id
        while id && (row = parents[id]) && path.size < 50
          path.unshift(row[1])
          id = row[0]
        end
        [ location.id, path.join(" › ") ]
      end
    end

    # One history line: what happened and where, without who or when.
    def unit_event_summary(event)
      words = UNIT_EVENT_WORDS.fetch(event.action, event.action.humanize)
      parts = [ words ]
      if ItemUnitEvent::RELOCATIONS.include?(event.action)
        target = event.to_unit ? event.to_unit.identifier_name : event.to_location&.name
        parts << (event.action == "install" ? "on" : "to") << target if target
        parts << "with #{event.via_unit.identifier_name}" if event.carried?
      elsif event.condition_before_id != event.condition_after_id
        parts << "#{event.condition_before&.name} → #{event.condition_after&.name}"
      elsif event.action == "received" && event.to_location
        parts << "into #{event.to_location.name}"
      end
      parts.compact.join(" ")
    end

    # Checks with readings, newest first, leaving out undone ones.
    def unit_readings_rows(unit)
      undone = unit.events.filter_map(&:reverses_id).to_set
      unit.events.select { |event| event.action == "check" && event.readings.present? && !event.reversal? && !undone.include?(event.id) }
        .reverse
    end

    # The newest value of each reading from those checks: { reading type id
    # => value }.
    def unit_latest_readings(rows)
      rows.reverse.each_with_object({}) { |event, latest| latest.merge!(event.readings) }
    end

    # "Hours (h)": a ReadingType's name and unit.
    def reading_heading(type)
      type.heading
    end
  end
end
