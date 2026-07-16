class TemporaryClosedDate < ApplicationRecord
  belongs_to :library

  validates :date, presence: true
  validates :date, uniqueness: { scope: :library_id, message: "はすでに臨時休館日として登録されています" }
  validates :label, presence: true

  scope :for_month, ->(month) { where(date: month.beginning_of_month..month.end_of_month) }
  scope :ordered, -> { order(:date) }
end
