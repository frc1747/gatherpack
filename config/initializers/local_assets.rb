# Assets are served from the app (Propshaft digests their names), so they can be
# cached for a year. Rails sends no Cache-Control for files in public/ unless an
# environment sets one; development and test set their own and are left alone.
Rails.application.config.public_file_server.headers = {
  "Cache-Control" => "public, max-age=#{1.year.to_i}, immutable"
}.freeze if Rails.application.config.public_file_server.headers.blank?
