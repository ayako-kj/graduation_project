class SpecialDate < ApplicationRecord
  belongs_to :library
  has_many :special_date_staffs, dependent: :destroy
  has_many :designated_staffs, through: :special_date_staffs, source: :staff

  validates :date, presence: true
  validates :label, presence: true
end
