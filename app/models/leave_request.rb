class LeaveRequest < ApplicationRecord
  belongs_to :staff

  validates :date, presence: true
  validates :staff_id, uniqueness: { scope: :date, message: "はすでにその日付で希望休が登録されています" }
  validate :no_hourly_leave_on_same_date

  # 希望休として登録・変更・削除した内容を、対応する実績（ActualLeave）にも
  # 反映する（ActualLeave側の逆方向の同期と対になる。公休は実績側に対応
  # する種別が無いため何もしない）
  after_save :sync_actual_leave!
  after_destroy :remove_synced_actual_leave!

  private

  # 終日休みはその日出勤していない前提のため、同じ日に時間休（出勤扱い）が
  # 既にある場合は矛盾するので登録できないようにする
  def no_hourly_leave_on_same_date
    return if staff_id.blank? || date.blank?
    return unless HourlyLeave.exists?(staff_id: staff_id, date: date)

    errors.add(:date, "はすでに時間休が登録されているため、希望休を登録できません")
  end

  def sync_actual_leave!
    leave_type = ActualLeave::LEAVE_TYPE_BY_REASON[reason]
    existing = ActualLeave.find_by(staff_id: staff_id, date: date)

    if leave_type.nil?
      existing&.destroy
      return
    end
    return if existing&.leave_type == leave_type

    existing ||= ActualLeave.new(staff_id: staff_id, date: date)
    existing.leave_type = leave_type
    existing.save!
  end

  def remove_synced_actual_leave!
    leave_type = ActualLeave::LEAVE_TYPE_BY_REASON[reason]
    return unless leave_type

    ActualLeave.where(staff_id: staff_id, date: date, leave_type: leave_type).destroy_all
  end
end
