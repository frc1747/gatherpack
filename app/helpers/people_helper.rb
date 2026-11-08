module PeopleHelper
  # Profile tabs registered by enabled features that this user may see. A
  # visible: check that raises hides its tab instead of breaking the profile.
  def feature_profile_tabs(person)
    GatherPack::Features.profile_tabs.select do |tab|
      tab.visible?(current_user, person)
    rescue => e
      Rails.logger.error("Profile tab #{tab.label.inspect} visibility check failed: #{e.class}: #{e.message}")
      false
    end
  end

  # An avatar that isn't an image Active Storage can resize (one stored before
  # uploads were checked), or isn't saved yet (a form shown again after its
  # upload was refused), shows the default picture instead of breaking the page.
  def get_avatar_url(avatar)
    avatar_shown?(avatar) ? url_for(avatar) : asset_path("default_profile.png")
  end

  def get_avatar_url_64(avatar)
    avatar_shown?(avatar) ? url_for(avatar.variant(resize_to_fill: [ 64, 64 ], format: :jpg)) : asset_path("default_profile.png")
  end

  def get_avatar_url_128(avatar)
    avatar_shown?(avatar) ? url_for(avatar.variant(resize_to_fill: [ 128, 128 ], format: :jpg)) : asset_path("default_profile.png")
  end

  def get_avatar_url_512(avatar)
    avatar_shown?(avatar) ? url_for(avatar.variant(resize_to_fill: [ 512, 512 ], format: :jpg)) : asset_path("default_profile.png")
  end

  def avatar_shown?(avatar)
    avatar.present? && avatar.attached? && avatar.variable? && avatar.blob.persisted?
  end

  def get_joinable_teams(person, current_user)
    if current_user.admin?
      return Team.all.to_a
    end

    (
      Team.where(join_permission: Team.join_permissions[:has_account]).includes(:team_type).to_a +
      person.teams.includes(:team_type).to_a +
      current_user.person.all_managed_teams.includes(:team_type).to_a
    ).uniq.sort_by { |t| [ t.team_type.name, t.name ] }
  end

  def person_as_badge(person, **opts)
    content = i("user") + " " + person.identifier_name
    if opts[:link]
      link_to person, class: "undecorated", data: { turbo_frame: "_top", turbo_prefetch: false } do
        tag.span content, class: "badge text-bg-primary"
      end
    else
      link_to person, class: "undecorated" do
        tag.span content, class: "badge text-bg-primary"
      end
    end
  end

  def person_time_clock_as_badge(person, hours, time_clock_period = nil)
    if time_clock_period
      total = if time_clock_period.available_hours > 0
        "#{hours} / #{pluralize(time_clock_period&.available_hours, "hour")}"
      else
        pluralize(hours, "hour")
      end
      content = safe_join([ total, i("hourglass-half"), time_clock_period.identifier_name ], " ")
      link_to time_clock_period_path(time_clock_period, q: { person_id_eq: person.id }), class: "undecorated", data: { turbo_frame: "_top" } do
        tag.span content, class: "badge text-bg-primary"
      end
    else
      content = pluralize(hours, "unallocated hour")
      link_to time_clock_punches_path(q: { person_id_eq: person.id }), class: "undecorated", data: { turbo_frame: "_top" } do
        tag.span content, class: "badge text-bg-primary"
      end
    end
  end
end
