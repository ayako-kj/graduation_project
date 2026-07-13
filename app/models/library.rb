class Library < ApplicationRecord
  has_many :admins, dependent: :nullify
  has_many :staffs, dependent: :destroy
  has_many :placement_rules, dependent: :destroy
  has_many :special_dates, dependent: :destroy
  has_many :shift_groups, dependent: :destroy
  has_many :assignments, dependent: :destroy
  has_many :mobile_libraries, dependent: :destroy

  validates :name, presence: true

  WDAY_NAMES = %w[日 月 火 水 木 金 土].freeze

  def closed_wdays_array
    JSON.parse(closed_wdays || "[]").map(&:to_i)
  rescue JSON::ParserError
    []
  end
end
