require "test_helper"

class AccountEnumerationTest < ActionDispatch::IntegrationTest
  PASSWORD = "Password1!"

  setup do
    host! "localhost"
    @member = User.create!(email: "member@example.com", password: PASSWORD)
    Person.create!(user: @member, first_name: "Max", last_name: "Member")
  end

  test "password reset does not reveal whether an address has an account" do
    post user_password_path, params: { user: { email: @member.email } }
    known = [ response.status, response.location, response.body.include?("not found") ]

    post user_password_path, params: { user: { email: "nobody-#{SecureRandom.hex(4)}@example.com" } }
    unknown = [ response.status, response.location, response.body.include?("not found") ]

    assert_equal known, unknown,
      "password reset answers differently for a member's address #{known.inspect} and an unknown one #{unknown.inspect} ([status, redirect, page says \"not found\"])"
  end

  test "password reset says the same thing for a member's address and an unknown one" do
    post user_password_path, params: { user: { email: @member.email } }
    known = flash[:notice]

    post user_password_path, params: { user: { email: "nobody@example.com" } }

    assert_equal known, flash[:notice]
    assert_match "If your email address exists", known
  end

  test "sign-in answers the same for a wrong password, an unknown address and a locked account" do
    answers = {}

    post user_session_path, params: { user: { email: @member.email, password: "wrong" } }
    answers[:wrong_password] = sign_in_answer

    post user_session_path, params: { user: { email: "nobody@example.com", password: "wrong" } }
    answers[:unknown_address] = sign_in_answer

    @member.update_columns(locked_at: Time.current, failed_attempts: Devise.maximum_attempts)
    post user_session_path, params: { user: { email: @member.email, password: PASSWORD } }
    answers[:locked] = sign_in_answer

    assert_equal 1, answers.values.uniq.size, "sign-in answers differ: #{answers.inspect}"
    assert_equal [ 422, "Invalid email or password." ], answers[:locked]
  end

  test "a reset request queues one job and sends nothing itself, whether or not the address has an account" do
    [ @member.email, "nobody@example.com" ].each do |email|
      assert_enqueued_jobs 1, only: SendResetPasswordInstructionsJob do
        assert_no_enqueued_jobs only: SendEmailJob do
          post user_password_path, params: { user: { email: " #{email.upcase} " } }
        end
      end
      assert_enqueued_with job: SendResetPasswordInstructionsJob, args: [ email ]
      assert_redirected_to new_user_session_path
      clear_enqueued_jobs
    end

    assert_nil @member.reload.reset_password_token, "the request itself set a reset token"
  end

  test "the reset job sends instructions to a login" do
    assert_enqueued_jobs 1, only: SendEmailJob do
      SendResetPasswordInstructionsJob.perform_now(@member.email)
    end
    assert @member.reload.reset_password_token.present?
  end

  test "the reset job sends instructions to a login without a person" do
    orphan = User.create!(email: "orphan@example.com", password: PASSWORD)

    assert_enqueued_jobs 1, only: SendEmailJob do
      SendResetPasswordInstructionsJob.perform_now(orphan.email)
    end
    body = enqueued_jobs.last[:args].last
    assert_includes body, "Hello orphan@example.com!"
  end

  test "the reset job does nothing for an unknown address" do
    assert_no_enqueued_jobs only: SendEmailJob do
      SendResetPasswordInstructionsJob.perform_now("nobody@example.com")
      SendResetPasswordInstructionsJob.perform_now("")
    end
  end

  private

  def sign_in_answer
    [ response.status, flash[:alert] ]
  end
end
