module ThemePalette
  # What "Use these as my starting colors" did, in words for the admin.
  ImportResult = Struct.new(:imported, :kept, :left_out, keyword_init: true) do
    def summary
      [
        imported.any? ? "Imported #{list(imported)}." : "No colors were imported.",
        ("Left out #{list(left_out)}: it wouldn't be readable on your colors." if left_out.any?),
        ("Still in your CSS variables: #{list(kept)}." if kept.any?)
      ].compact.join(" ")
    end

    private

    # The flash lives in the session cookie, so long lists are cut short.
    def list(names, limit: 8)
      shown = names.first(limit).map { |name| name.truncate(40) }
      shown << "#{names.size - limit} more" if names.size > limit
      shown.to_sentence
    end
  end
end
