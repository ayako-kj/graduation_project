class SpecialDate < ApplicationRecord
  TARGET_GROUPS = %w[全職員 正規職員 専門司書 司書 行政職 一般事務].freeze
  TARGET_GROUP_OPTIONS = [["グループ指定なし", ""]] + TARGET_GROUPS.map { |group| [group, group] }

  belongs_to :library
  belongs_to :created_by_staff, class_name: "Staff", optional: true
  has_many :special_date_staffs, dependent: :destroy
  has_many :designated_staffs, through: :special_date_staffs, source: :staff

  # コントローラーが保存前にセットする、送信された個別指定の対象者IDの一時保持用。
  # designated_staffs は中間テーブル経由のため、保存前のバリデーションでは使えない。
  attr_accessor :designated_staff_ids_input

  validates :date, presence: true
  validates :label, presence: true
  validates :date, uniqueness: { scope: [:library_id, :label], message: "と名称の組み合わせはすでに登録されています" }
  validate :target_presence
  validate :end_time_after_start_time

  def time_range_label
    return nil if start_time.blank? && end_time.blank?
    return "#{start_time.strftime('%H:%M')}〜#{end_time.strftime('%H:%M')}" if start_time.present? && end_time.present?
    return "#{start_time.strftime('%H:%M')}〜" if start_time.present?

    "〜#{end_time.strftime('%H:%M')}"
  end

  private

  def target_presence
    return if target_group.present?
    return if designated_staff_ids_input.present?

    errors.add(:base, "対象者を1人以上選択してください")
  end

  def end_time_after_start_time
    return if start_time.blank? || end_time.blank?

    errors.add(:end_time, "は開始時刻より後に設定してください") if end_time <= start_time
  end
end
