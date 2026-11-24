# Included into User from config/initializers/phone_notifications.rb.
module PushNotifiable
  extend ActiveSupport::Concern

  included do
    has_many :push_subscriptions, dependent: :destroy
    has_one :push_preference, dependent: :destroy
  end

  def enabled_push_topics
    (push_preference&.enabled_topics || GatherPack::PushTopics.default_keys).map(&:to_sym)
  end

  def push_topic_enabled?(topic)
    GatherPack::PushTopics[topic].present? && enabled_push_topics.include?(topic.to_sym)
  end
end
