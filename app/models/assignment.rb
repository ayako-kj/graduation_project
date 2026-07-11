class Assignment < ApplicationRecord
  belongs_to :library
  has_many :staff_assignments, dependent: :destroy
  has_many :staffs, through: :staff_assignments

  WDAY_NAMES = %w[日曜日 月曜日 火曜日 水曜日 木曜日 金曜日 土曜日].freeze

  validates :name, presence: true

  def meeting_wday_name
    return nil if meeting_wday.nil?
    WDAY_NAMES[meeting_wday]
  end
end
