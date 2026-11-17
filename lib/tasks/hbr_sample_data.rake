# Fork-only: loads the Northwind sample data for the features in this build.
# See fork/sample_data/README.md and fork/specs/sample-data-spec.md.
#
#   bin/rails hbr:sample_data
#
# SAMPLE_DATA_FORCE=1 loads it into a database that has real data.
# SAMPLE_DATA_STRICT=1 (CI) fails when a manifest branch has no sample data.
namespace :hbr do
  desc "Load the Northwind sample data for the features in this build"
  task sample_data: :environment do
    require Rails.root.join("fork/sample_data/sample_data.rb").to_s

    warnings = Hbr::SampleData.run(root: Rails.root.to_s, force: ENV["SAMPLE_DATA_FORCE"] == "1")
    puts "Sample data loaded. Sign in as admin@example.com / #{Hbr::SampleData::PASSWORD}. " \
      "Restart the app so it sees the feature settings."
    abort "Missing sample data (SAMPLE_DATA_STRICT=1)." if warnings.any? && ENV["SAMPLE_DATA_STRICT"] == "1"
  rescue Hbr::SampleData::Error => e
    abort e.message
  end
end
