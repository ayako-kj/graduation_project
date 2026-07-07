class Staff < ApplicationRecord
  belongs_to :staff_type
  belongs_to :employment_type

  validates :name, presence: true
end
