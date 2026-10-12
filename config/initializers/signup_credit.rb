# Sign-ups as a credit source for commitments, and the commitments hint in
# the sign up dialog: the one place that knows both layers (spec §4.8).
# Uses config.to_prepare, like commitments.rb and signups.rb, so the
# registrations come back after a development reload.
Rails.application.config.to_prepare do
  # A kind has one subject type, so a whole sheet and one position are two
  # kinds sharing an implementation.
  Commitments.register_source(:signups, Commitments::SignupSource)
  Commitments.register_source(:signup_positions, Commitments::SignupPositionSource)

  Signups.extensions.register_on_behalf_of_hint(:commitments, ->(sheet, person) { Commitments::SignupHint.call(sheet, person) })

  # The hint shows progress only to those who may see it, so it needs to
  # know who is signing up.
  SignupsController.before_action { Commitments::SignupViewer.person = current_user&.person }
end
