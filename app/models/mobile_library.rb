class MobileLibrary < ApplicationRecord
  belongs_to :library
  has_many :mobile_library_routes, dependent: :destroy

  validates :name, presence: true
end
