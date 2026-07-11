class Library < ApplicationRecord
  has_many :admins, dependent: :nullify
  has_many :staffs, dependent: :destroy
  has_many :placement_rules, dependent: :destroy
  has_many :special_dates, dependent: :destroy
  has_many :shift_groups, dependent: :destroy
  has_many :assignments, dependent: :destroy

  validates :name, presence: true
end
