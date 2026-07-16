class SpecialDate < ApplicationRecord
  TARGET_GROUPS = %w[全職員 正規職員 専門司書 司書 行政職 一般事務].freeze

  belongs_to :library
  belongs_to :created_by_staff, class_name: "Staff", optional: true
  has_many :special_date_staffs, dependent: :destroy
  has_many :designated_staffs, through: :special_date_staffs, source: :staff

  validates :date, presence: true
  validates :label, presence: true
  validates :date, uniqueness: { scope: [:library_id, :label], message: "と名称の組み合わせはすでに登録されています" }
end
