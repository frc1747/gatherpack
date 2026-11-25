# What every accounting source promises (Accounting::Provider). Include it
# in a source's test and define:
#
#   provider_source  -> the source under test
#   provider_cases   -> [[entity_type, raw data, { column => expected }], ...]
#                       covering every type in entity_types
#
# and, for a source with :create_charges,
#
#   provider_billing_line -> a saved AccountingBillingLine the source can bill
#   provider_charge_count -> how many charges the source holds now
module Accounting
  module ProviderContract
    WRITES = {
      create_charges: ->(source) { source.create_charge(Struct.new(:request_id).new("req-1")) },
      create_customers: ->(source) { source.create_customer(Person.new, email: "a@example.com", request_id: SecureRandom.uuid) },
      send_charges: ->(source) { source.send_charge("1", email: "a@example.com") }
    }.freeze

    def self.included(base)
      base.class_eval do
        test "provider contract: capabilities are known ones" do
          assert_empty provider_source.capabilities.to_a - Accounting::Provider::CAPABILITIES
        end

        test "provider contract: every entity type has a case" do
          assert_empty provider_source.entity_types.keys - provider_cases.map(&:first)
        end

        test "provider contract: records normalize to the expected neutral columns" do
          provider_cases.each do |entity_type, data, expected|
            columns = provider_source.normalize(entity_type, data)

            assert_empty columns.keys - AccountingRecord::NEUTRAL_COLUMNS, "#{entity_type} fills columns that aren't neutral"
            assert_includes Array.wrap(provider_source.entity_types[entity_type]).map(&:to_s), columns[:role], "#{entity_type} role"
            expected.each do |column, value|
              value.nil? ? assert_nil(columns[column], "#{entity_type} #{column}") : assert_equal(value, columns[column], "#{entity_type} #{column}")
            end

            record = provider_source.accounting_records.new(columns.merge(entity_type: entity_type,
              external_id: provider_source.external_id(entity_type, data), revision: provider_source.revision(entity_type, data), data: data))
            assert record.valid?, "#{entity_type}: #{record.errors.full_messages.to_sentence}"
          end
        end

        test "provider contract: normalize is pure" do
          provider_cases.each do |entity_type, data, _|
            before = data.deep_dup
            assert_equal provider_source.normalize(entity_type, data), provider_source.normalize(entity_type, data.deep_dup)
            assert_equal before, data, "#{entity_type} normalize changed its input"
          end
        end

        test "provider contract: public_label never contains a description" do
          provider_cases.each do |entity_type, data, _|
            columns = provider_source.normalize(entity_type, data)
            next if columns[:description].blank? || columns[:public_label].blank?

            columns[:description].lines.map(&:strip).compact_blank.each do |line|
              assert_not_includes columns[:public_label], line, "#{entity_type} public_label shows its description"
            end
          end
        end

        test "provider contract: create_charge twice with one request id makes one charge" do
          # Sources that don't create charges are checked below: create_charge raises.
          return pass unless provider_source.capabilities.include?(:create_charges)

          line = provider_billing_line
          before = provider_charge_count
          first = provider_source.create_charge(line)
          second = provider_source.create_charge(AccountingBillingLine.find(line.id))

          assert first.present?
          assert_equal first, second
          assert_equal before + 1, provider_charge_count
        end

        test "provider contract: undeclared capabilities raise NotImplementedError" do
          WRITES.each do |capability, call|
            next if provider_source.capabilities.include?(capability)

            assert_raises(NotImplementedError, capability.to_s) { call.call(provider_source) }
          end
          unless provider_source.capabilities.include?(:change_feed)
            assert_raises(NotImplementedError) { provider_source.each_change(provider_source.entity_types.keys, 1.day.ago) { } }
          end
          unless provider_source.capabilities.include?(:notifications)
            assert_raises(NotImplementedError) { provider_source.fetch_record(provider_source.entity_types.keys.first, "1") }
          end
        end
      end
    end
  end
end
