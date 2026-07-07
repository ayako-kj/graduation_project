class EmploymentType < ApplicationRecord
  has_many :staffs, dependent: :restrict_with_error

  validates :name, presence: true
end
