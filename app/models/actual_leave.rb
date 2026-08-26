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

  # LeaveRequest#reason（希望休の種別文言）との対応。公休は実績側に
  # 対応する種別が無いため含まない
  REASON_BY_LEAVE_TYPE = {
    "annual"  => "年休",
    "summer"  => "夏期休暇",
    "special" => "特別休暇",
    "sick"    => "病気休暇"
  }.freeze
  LEAVE_TYPE_BY_REASON = REASON_BY_LEAVE_TYPE.invert.freeze

  belongs_to :staff

  validates :date, presence: true
  validates :leave_type, inclusion: { in: LEAVE_TYPES.keys }
  validates :staff_id, uniqueness: { scope: :date }

  # シフト表のセル編集・休暇種別入力画面のどちらから実績を登録しても、
  # 対応する希望休（LeaveRequest）にも同じ内容が反映されるようにする
  # （最終的には職員の了承を得て希望休として登録するため、実績と希望休は
  # 同じものとして扱ってよいという方針）
  after_save :sync_leave_request!
  after_destroy :remove_synced_leave_request!

  private

  def sync_leave_request!
    reason = REASON_BY_LEAVE_TYPE[leave_type]
    return unless reason

    lr = LeaveRequest.find_or_initialize_by(staff_id: staff_id, date: date)
    return if lr.persisted? && lr.reason == reason

    lr.reason = reason
    lr.save!
  end

  def remove_synced_leave_request!
    reason = REASON_BY_LEAVE_TYPE[leave_type]
    return unless reason

    LeaveRequest.where(staff_id: staff_id, date: date, reason: reason).destroy_all
  end
end
