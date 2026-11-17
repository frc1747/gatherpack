# Checks the files being attached to an Active Storage attachment: their
# content type, as Active Storage identifies it from the file's bytes rather
# than as the browser declared it, and their size.
#
#   validates :avatar, attachment: { content_types: AttachmentValidator::IMAGE_TYPES, max_size: 5.megabytes }
#
# Only files being attached are checked, so a record that already holds a
# file from before a limit was added can still be saved.
class AttachmentValidator < ActiveModel::EachValidator
  # Image types the app can resize. SVG is left out: it can carry scripts.
  IMAGE_TYPES = %w[image/png image/jpeg image/webp].freeze

  def check_validity!
    raise ArgumentError, ":content_types or :max_size is required" unless options[:content_types] || options[:max_size]
  end

  def validate_each(record, attribute, _value)
    new_blobs(record, attribute).each do |blob|
      if options[:content_types] && options[:content_types].exclude?(blob.content_type)
        add_error(record, attribute, "must be a #{type_names.to_sentence(two_words_connector: " or ", last_word_connector: " or ")} file")
      end

      if options[:max_size] && blob.byte_size > options[:max_size]
        add_error(record, attribute, "must be smaller than #{ActiveSupport::NumberHelper.number_to_human_size(options[:max_size])}")
      end
    end
  end

  private

  def new_blobs(record, attribute)
    change = record.attachment_changes[attribute.to_s]
    attachments = change.respond_to?(:attachments) ? change.attachments : Array(change.try(:attachment))
    attachments.reject(&:persisted?).map(&:blob)
  end

  def type_names
    options[:content_types].map { |type| type.split("/").last.upcase }
  end

  def add_error(record, attribute, message)
    record.errors.add(attribute, message) unless record.errors.added?(attribute, message)
  end
end
