module GatherPack
  # Lets a feature ship its own SolidQueue recurring tasks in
  # config/recurring.d/*.yml instead of editing config/recurring.yml.
  # Each file uses the same format as recurring.yml (tasks at the top level,
  # or nested under an environment name).
  #
  # config/recurring.yml renders `GatherPack::RecurringSchedule.yaml` through
  # ERB, which SolidQueue runs when it parses the file, so no SolidQueue
  # internals are involved.
  module RecurringSchedule
    class DuplicateTask < StandardError; end

    TASK_KEYS = %i[class command schedule].freeze

    class << self
      attr_writer :directory

      def directory
        @directory || Rails.root.join("config/recurring.d")
      end

      # Tasks from every *.yml file in the directory, keyed by task name.
      def tasks(env: Rails.env)
        Dir[File.join(directory, "*.yml")].sort.each_with_object({}) do |file, tasks|
          config = ActiveSupport::ConfigurationFile.parse(file).deep_symbolize_keys
          config = config[env.to_sym] || {} if env_scoped?(config)

          config.each do |name, options|
            raise DuplicateTask, "Recurring task #{name} in #{file} is defined more than once" if tasks.key?(name)

            tasks[name] = options
          end
        end
      end

      # The tasks as top-level YAML keys, for config/recurring.yml. Put it
      # above that file's own tasks: when a name appears twice YAML keeps the
      # last one, so a task in recurring.yml wins over a fragment's.
      def yaml(env: Rails.env)
        tasks = self.tasks(env: env)
        tasks.empty? ? "" : tasks.deep_stringify_keys.to_yaml.delete_prefix("---\n")
      end

      private

      # A file is scoped to environments when a top-level entry isn't a task.
      def env_scoped?(config)
        config.values.any? { |value| value.is_a?(Hash) && (value.keys & TASK_KEYS).empty? }
      end
    end
  end
end
