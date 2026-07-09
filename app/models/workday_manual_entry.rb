class WorkdayManualEntry < ApplicationRecord
  belongs_to :staff

  validates :year_month, presence: true
  validates :working_days, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :staff_id, uniqueness: { scope: :year_month, message: "はすでにその月のデータが登録されています" }
end
