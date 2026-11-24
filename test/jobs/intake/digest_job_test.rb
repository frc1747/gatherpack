require "test_helper"
require_relative "../../support/intake_world"

class Intake::DigestJobTest < ActiveJob::TestCase
  include IntakeWorld

  setup do
    build_intake_world
    %w[Ann Bea].each { |first| MembershipApplication.create!(person: Person.create!(first_name: first, last_name: "Lee"), team: @juniors, registration: @registration) }
    MembershipApplication.create!(person: Person.create!(first_name: "Cal", last_name: "Lee"), team: @mentors, registration: @registration)
    MembershipApplication.create!(person: Person.create!(first_name: "Dee", last_name: "Lee"), team: @mentors) # not from a registration
  end

  def digests
    enqueued_jobs.select { |job| job[:job] == SendEmailJob }.map { |job| [ job[:args].second, job[:args].fourth ] }
  end

  test "each manager gets one message listing the teams they manage" do
    with_intake { Intake::DigestJob.perform_now }

    by_address = digests.to_h
    assert_equal 2, by_address.size
    northwind = by_address.fetch(@leader.user.email)
    assert_match "2 people are waiting to join Juniors.", northwind
    assert_match "1 person is waiting to join Mentors.", northwind
    juniors = by_address.fetch(@juniors_leader.user.email)
    assert_match "2 people are waiting to join Juniors.", juniors
    assert_no_match "Mentors", juniors
  end

  test "at most one a day per manager" do
    with_intake do
      Intake::DigestJob.perform_now
      Intake::DigestJob.perform_now
    end

    assert_equal 2, digests.size
  end

  test "nothing with the feature off, or nobody waiting" do
    Intake::DigestJob.perform_now
    assert_empty digests

    MembershipApplication.where.not(registration_id: nil).find_each(&:deny!)
    with_intake { Intake::DigestJob.perform_now }
    assert_empty digests
  end
end
