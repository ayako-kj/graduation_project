class Staff < ApplicationRecord
  belongs_to :library
  belongs_to :staff_type
  belongs_to :employment_type

  has_many :shifts, dependent: :destroy
  has_many :leave_requests, dependent: :destroy
  has_many :hourly_leaves, dependent: :destroy
  has_many :special_date_staffs, dependent: :destroy
  has_many :actual_leaves, class_name: "ActualLeave", dependent: :destroy
  has_many :workday_manual_entries, dependent: :destroy
  has_many :staff_assignments, dependent: :destroy
  has_many :assignments, through: :staff_assignments
  has_many :mobile_library_staff_assignments, dependent: :destroy
  has_many :monthly_submissions, dependent: :destroy

  validates :name, presence: true

  before_create :generate_access_token

  WDAY_NAMES = %w[日 月 火 水 木 金 土].freeze

  # 指定した期間（start_date〜end_date）のいずれかの日に在籍していた
  # 職員を絞り込む。hired_on/retired_onが未設定の場合はそれぞれ
  # 「ずっと前から在籍」「まだ在籍中」とみなす
  scope :active_during, lambda { |start_date, end_date|
    where("hired_on IS NULL OR hired_on <= ?", end_date)
      .where("retired_on IS NULL OR retired_on >= ?", start_date)
  }

  # 指定した1日時点で在籍していた職員を絞り込む（担当者選択など、
  # 月をまたがず「今現在」を基準にする画面で使う）
  scope :active_on, ->(date) { active_during(date, date) }

  def retired?
    retired_on.present? && retired_on < Date.today
  end

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
