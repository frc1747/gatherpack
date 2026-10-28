module Commitments
  # The interface a credit source kind provides (spec §4.2). Subclasses
  # implement the class methods for choosing a subject and the instance
  # methods for one CommitmentSource.
  class SourceKind
    attr_reader :source

    def initialize(source)
      @source = source
    end

    # The kind's name in the source picker ("Check-ins").
    def self.label
      raise NotImplementedError
    end

    # The class a source of this kind points at ("EventType").
    def self.subject_type
      raise NotImplementedError
    end

    # The subjects this person may add to the commitment (who may add it).
    def self.subject_choices(commitment, person)
      raise NotImplementedError
    end

    def self.subject_allowed?(commitment, person, subject)
      subject.present? && subject_choices(commitment, person).exists?(id: subject.id)
    end

    # Names of the notifications that should trigger a recompute.
    def self.watches
      []
    end

    # Credit records for these people, within the commitment's period.
    def records(person_ids)
      raise NotImplementedError
    end

    # Credit records whoever they credit, done by these workers, so a worker's
    # record at an event counts for one person however progress is asked
    # for. A kind whose records can credit someone other than the worker
    # (worker_id set) overrides this; otherwise the worker is the person
    # credited.
    def records_by_workers(worker_ids)
      records(worker_ids).select { |record| worker_ids.include?(record.worker) }
    end

    # A HowToEarn for a person's commitment page.
    def how_to_earn
      raise NotImplementedError
    end

    def commitment
      source.commitment
    end
  end
end
