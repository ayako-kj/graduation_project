class MonthlySubmission < ApplicationRecord
  belongs_to :staff

  validates :target_month, presence: true
  validates :staff_id, uniqueness: { scope: :target_month }

  before_validation { self.target_month = target_month.beginning_of_month if target_month.present? }
end
