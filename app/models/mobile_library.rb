class MobileLibrary < ApplicationRecord
  belongs_to :library
  has_many :mobile_library_routes, dependent: :destroy
  has_many :special_dates, dependent: :nullify

  validates :name, presence: true
end
