class Staff < ApplicationRecord
  belongs_to :staff_type
  belongs_to :employment_type

  has_many :shifts, dependent: :destroy
  has_many :leave_requests, dependent: :destroy
  has_many :special_date_staffs, dependent: :destroy
  has_many :workday_manual_entries, dependent: :destroy

  validates :name, presence: true
end
