class MobileLibraryRoute < ApplicationRecord
  Occurrence = Struct.new(:date, :staffs, keyword_init: true)

  belongs_to :mobile_library
  has_many :mobile_library_staff_assignments, dependent: :destroy
  has_many :staffs, through: :mobile_library_staff_assignments
  has_many :mobile_library_exceptions, dependent: :destroy

  WDAY_NAMES = %w[日曜日 月曜日 火曜日 水曜日 木曜日 金曜日 土曜日].freeze
  WEEK_LABELS = { 1 => "第1", 2 => "第2", 3 => "第3", 4 => "第4" }.freeze

  validates :name, presence: true
  validates :wday, inclusion: { in: 0..6 }
  validates :week_number, inclusion: { in: 1..4 }

  def schedule_label
    "#{WEEK_LABELS[week_number]}#{WDAY_NAMES[wday]}"
  end

  # 対象月におけるこのコースの実際の巡回日・担当者を返す（例外による上書きを反映）。
  # 巡回日が休館日と重なる場合や、担当者が誰もいない場合はnilを返す。
  def occurrence_for(target_month, closed_days: {})
    month = target_month.beginning_of_month
    # includesでプリロード済みの配列をそのまま検索し、N+1クエリを避ける
    exception = mobile_library_exceptions.find { |e| e.target_month == month }
    date = exception&.date || default_date_for(target_month)
    return nil if date.nil? || closed_days.key?(date)

    occurrence_staffs = exception && exception.staffs.any? ? exception.staffs.to_a : staffs.to_a
    return nil if occurrence_staffs.empty?

    Occurrence.new(date: date, staffs: occurrence_staffs)
  end

  private

  def default_date_for(target_month)
    dates_of_wday = (target_month.beginning_of_month..target_month.end_of_month).select { |d| d.wday == wday }
    dates_of_wday[week_number - 1]
  end
end
