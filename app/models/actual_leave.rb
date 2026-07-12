class ActualLeave < ApplicationRecord
  LEAVE_TYPES = {
    "annual"  => "年",
    "summer"  => "夏",
    "special" => "特",
    "sick"    => "病"
  }.freeze

  LEAVE_LABELS = {
    "annual"  => "年休",
    "summer"  => "夏季休暇",
    "special" => "特別休暇",
    "sick"    => "病気休暇"
  }.freeze

  belongs_to :staff

  validates :date, presence: true
  validates :leave_type, inclusion: { in: LEAVE_TYPES.keys }
  validates :staff_id, uniqueness: { scope: :date }
end
