class HourlyLeave < ApplicationRecord
  belongs_to :staff

  validates :date, presence: true
  validates :staff_id, uniqueness: { scope: :date, message: "はすでにその日付で時間休が登録されています" }
  validate :time_range_label_presence
  validate :no_full_day_leave_on_same_date

  private

  def time_range_label_presence
    return if time_range_label.present?

    date_label = date.present? ? date.strftime("%-m/%-d") : ""
    errors.add(:base, "時間休#{date_label}の時間帯を入力してください。")
  end

  # 時間休はその日出勤している前提のため、同じ日に終日休み（希望休）が
  # 既にある場合は矛盾するので登録できないようにする
  def no_full_day_leave_on_same_date
    return if staff_id.blank? || date.blank?
    return unless LeaveRequest.exists?(staff_id: staff_id, date: date)

    errors.add(:date, "はすでに希望休が登録されているため、時間休を登録できません")
  end
end
