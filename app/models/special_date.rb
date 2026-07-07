class SpecialDate < ApplicationRecord
  validates :date, presence: true
  validates :label, presence: true
end
