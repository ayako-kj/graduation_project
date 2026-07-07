class LeaveRequest < ApplicationRecord
  belongs_to :staff

  validates :date, presence: true
  validates :staff_id, uniqueness: { scope: :date, message: "はすでにその日付で希望休が登録されています" }
end
