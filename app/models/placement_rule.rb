class PlacementRule < ApplicationRecord
  belongs_to :staff_type

  validates :min_count, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
