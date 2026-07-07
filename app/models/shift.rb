class Shift < ApplicationRecord
  belongs_to :shift_group
  belongs_to :staff

  validates :date, presence: true
  validates :is_working, inclusion: { in: [true, false] }
end
