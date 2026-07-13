class WorkdayManualEntry < ApplicationRecord
  belongs_to :staff

  validates :year_month, presence: true
  validates :working_days, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :early_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :post_duty_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :holiday_post_duty_count, numericality: { greater_than_or_equal_to: 0, only_integer: true }, allow_nil: true
  validates :staff_id, uniqueness: { scope: :year_month, message: "はすでにその月のデータが登録されています" }

  def blank?
    working_days.nil? && early_count.nil? && post_duty_count.nil? && holiday_post_duty_count.nil? && note.blank?
  end
end
