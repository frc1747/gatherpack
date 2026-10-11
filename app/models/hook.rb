class Hook < ApplicationRecord
  has_neat_id :hook
  has_paper_trail versions: { class_name: "AuditLog" }

  validates :name, presence: true

  # Events that aren't model callbacks. Register them from a model's class
  # body or from a config.to_prepare block, so they come back after code
  # reloading in development:
  #
  #   Hook.register_event "token - activate"
  def self.register_event(event)
    registered_events << event
  end

  def self.registered_events
    @registered_events ||= Set.new
  end

  register_event "token - activate"

  # Every event a hook can listen for: create, update and destroy for each
  # model that includes CanBeHooked, plus the registered events.
  def self.catalog
    (hooked_model_events + registered_events.to_a).uniq.sort
  end

  def self.hooked_model_events
    # Load every model so ApplicationRecord.descendants is complete when
    # eager loading is off (test, console). Already loaded files are skipped.
    Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/models"))

    ApplicationRecord.descendants
      .select { |model| model.include?(CanBeHooked) && !model.abstract_class? }
      .map(&:table_name)
      .uniq
      .flat_map { |table| [ "create", "update", "destroy" ].map { |action| "#{table} - #{action}" } }
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[ name event updated_at ]
  end

  def identifier_icon
    "timeline"
  end

  def run(model)
    eval(code, binding, name, 0)
  end
end
