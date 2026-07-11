class MobileLibraryRoute < ApplicationRecord
  belongs_to :mobile_library
  has_many :mobile_library_staff_assignments, dependent: :destroy
  has_many :staffs, through: :mobile_library_staff_assignments

  WDAY_NAMES = %w[日曜日 月曜日 火曜日 水曜日 木曜日 金曜日 土曜日].freeze
  WEEK_LABELS = { 1 => "第1", 2 => "第2", 3 => "第3", 4 => "第4" }.freeze

  validates :name, presence: true
  validates :wday, inclusion: { in: 0..6 }
  validates :week_number, inclusion: { in: 1..4 }

  def schedule_label
    "#{WEEK_LABELS[week_number]}#{WDAY_NAMES[wday]}"
  end
end
