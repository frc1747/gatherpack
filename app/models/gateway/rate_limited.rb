# Raised by a sending gateway when its service refuses a message for now
# because too many were sent too quickly (HTTP 429, SMTP 4xx "busy").
# SendEmailJob retries these, so a burst of notices goes out a little later
# instead of being dropped.
class Gateway::RateLimited < StandardError
end
