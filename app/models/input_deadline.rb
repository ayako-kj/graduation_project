class InputDeadline < ApplicationRecord
  belongs_to :library

  validates :target_month, presence: true
  validates :library_id, uniqueness: { scope: :target_month }

  before_validation { self.target_month = target_month.beginning_of_month if target_month.present? }
end
