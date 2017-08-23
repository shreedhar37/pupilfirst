# encoding: utf-8
# frozen_string_literal: true

class Resource < ApplicationRecord
  include FriendlyId
  friendly_id :slug_candidates, use: %i[slugged finders]
  acts_as_taggable

  belongs_to :startup, optional: true
  belongs_to :level, optional: true
  belongs_to :target, optional: true

  def slug_candidates
    [
      :title,
      %i[title updated_at]
    ]
  end

  def should_generate_new_friendly_id?
    title_changed? || saved_change_to_title? || super
  end

  validates :title, presence: true
  validates :description, presence: true

  validate :file_or_video_embed_must_be_present

  def file_or_video_embed_must_be_present
    return if file.present? || video_embed.present?

    errors[:base] << 'A video embed or file is required.'
  end

  mount_uploader :file, ResourceFileUploader
  mount_uploader :thumbnail, ResourceThumbnailUploader

  scope :public_resources, -> { where(level_id: nil).order('title') }
  # scope to search title
  scope :title_matches, ->(search_key) { where("lower(title) LIKE ?", "%#{search_key.downcase}%") }

  # Custom scope to allow AA to filter by intersection of tags.
  scope :ransack_tagged_with, ->(*tags) { tagged_with(tags) }

  def self.ransackable_scopes(_auth)
    %i[ransack_tagged_with]
  end

  delegate :content_type, to: :file

  def level_exclusive?
    level.present?
  end

  def stream?
    video_embed.present? || content_type.end_with?('/mp4')
  end

  def increment_downloads(user)
    update!(downloads: downloads + 1)
    if user.present?
      Users::ActivityService.new(user).create(UserActivity::ACTIVITY_TYPE_RESOURCE_DOWNLOAD, 'resource_id' => id)
    end
  end

  after_create do
    Resources::AfterCreateNotificationJob.perform_later(self)
  end

  # Ensure titles are capitalized.
  before_save do
    self.title = title.titlecase(humanize: false, underscore: false)
  end
end
