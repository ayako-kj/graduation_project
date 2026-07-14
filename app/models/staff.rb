class Staff < ApplicationRecord
  belongs_to :library
  belongs_to :staff_type
  belongs_to :employment_type

  has_many :shifts, dependent: :destroy
  has_many :leave_requests, dependent: :destroy
  has_many :special_date_staffs, dependent: :destroy
  has_many :actual_leaves, dependent: :destroy
  has_many :workday_manual_entries, dependent: :destroy
  has_many :staff_assignments, dependent: :destroy
  has_many :assignments, through: :staff_assignments

  validates :name, presence: true

  before_create :generate_access_token

  WDAY_NAMES = %w[日 月 火 水 木 金 土].freeze

  def unavailable_wdays_array
    JSON.parse(unavailable_wdays || "[]")
  rescue JSON::ParserError
    []
  end

  def unavailable_wdays_label
    unavailable_wdays_array.map { |w| "#{WDAY_NAMES[w]}曜日" }.join("・")
  end

  def effective_daily_work_hours
    daily_work_hours || employment_type.daily_work_hours
  end

  def regenerate_token!
    update!(access_token: SecureRandom.urlsafe_base64(16))
  end

  private

  def generate_access_token
    self.access_token ||= SecureRandom.urlsafe_base64(16)
  end
end
