class EmploymentType < ApplicationRecord
  has_many :staffs, dependent: :restrict_with_error

  validates :name, presence: true
  validates :daily_work_hours, :city_hall_daily_hours,
            presence: true, numericality: { greater_than: 0 }
end
