module GatherPack
  # Lets a feature ship its own SolidQueue recurring tasks in
  # config/recurring.d/*.yml instead of editing config/recurring.yml.
  # Each file uses the same format as recurring.yml (tasks at the top level,
  # or nested under an environment name).
  module RecurringSchedule
    class DuplicateTask < StandardError; end

    class << self
      attr_writer :directory

      def directory
        @directory || Rails.root.join("config/recurring.d")
      end

      # Tasks from every *.yml file in the directory, keyed by task name.
      def tasks(env: Rails.env)
        Dir[File.join(directory, "*.yml")].sort.each_with_object({}) do |file, tasks|
          config = ActiveSupport::ConfigurationFile.parse(file).deep_symbolize_keys
          config = config[env.to_sym] if config[env.to_sym].is_a?(Hash)

          config.each do |name, options|
            raise DuplicateTask, "Recurring task #{name} in #{file} is defined more than once" if tasks.key?(name)

            tasks[name] = options
          end
        end
      end
    end

    # Prepended to SolidQueue::Configuration: adds the fragments to the tasks
    # read from config/recurring.yml. Tasks in recurring.yml win on a clash.
    module ConfigurationExtension
      private

      def recurring_tasks_config
        @recurring_tasks_config ||= GatherPack::RecurringSchedule.tasks.merge(super)
      end
    end
  end
end
