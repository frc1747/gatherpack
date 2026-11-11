# Be sure to restart your server when you modify this file.

# Define an application-wide HTTP permissions policy. For further
# information see: https://developer.mozilla.org/docs/Web/HTTP/Headers/Permissions-Policy
#
# Rails' config.permissions_policy still sends the older Feature-Policy header,
# so the Permissions-Policy header is set directly. The camera is used by photo
# capture; Stripe payments redirect to Stripe Checkout rather than embedding it.
Rails.application.config.action_dispatch.default_headers["Permissions-Policy"] = [
  "camera=(self)",
  "microphone=()",
  "geolocation=()",
  "usb=()",
  "payment=()",
  "gyroscope=()",
  "magnetometer=()",
  "accelerometer=()"
].join(", ")
