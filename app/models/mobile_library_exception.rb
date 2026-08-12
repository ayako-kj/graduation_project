class MobileLibraryException < ApplicationRecord
  belongs_to :mobile_library_route
  has_many :mobile_library_exception_staffs, dependent: :destroy
  has_many :staffs, through: :mobile_library_exception_staffs

  # コントローラーが保存前にセットする、送信された担当者変更のIDの一時保持用。
  # staffs は中間テーブル経由のため、保存前のバリデーションでは使えない。
  attr_accessor :staff_ids_input

  before_validation :normalize_target_month

  validates :target_month, presence: true
  validates :target_month, uniqueness: { scope: :mobile_library_route_id, message: "の例外はすでに登録されています" }
  validate :override_presence
  validate :date_within_target_month

  private

  def normalize_target_month
    self.target_month = target_month.beginning_of_month if target_month.present?
  end

  def override_presence
    return if date.present?
    return if staff_ids_input.present?

    errors.add(:base, "巡回日または担当者のいずれかを変更してください")
  end

  def date_within_target_month
    return if date.blank? || target_month.blank?

    errors.add(:date, "は対象月の中の日付にしてください") unless date.between?(target_month.beginning_of_month, target_month.end_of_month)
  end
end
