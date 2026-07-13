class ShiftSnapshot < ApplicationRecord
  belongs_to :library

  validates :target_month, :snapshot_data, :confirmed_at, presence: true

  def shifts_data
    JSON.parse(snapshot_data)
  end

  def confirmed_at_jst
    confirmed_at.in_time_zone("Tokyo")
  end
end
