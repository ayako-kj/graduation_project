class ShiftGroup < ApplicationRecord
  has_many :shifts, dependent: :destroy

  validates :target_month, presence: true
  validates :status, presence: true
end
