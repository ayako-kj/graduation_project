class WorkingDayCalculator
  # 市役所の年末年始閉庁期間（12/29〜1/3）。国民の祝日とは別に市役所独自で
  # 閉庁するため、祝日データには含まれない。市役所基準の勤務日数からは
  # この期間を除外する
  YEAR_END_NEW_YEAR_MONTH_DAYS = [[12, 29], [12, 30], [12, 31], [1, 1], [1, 2], [1, 3]].freeze

  def initialize(target_month, holidays, closed_wdays: [2])
    @start_date   = target_month.beginning_of_month
    @end_date     = target_month.end_of_month
    @holidays     = holidays
    @closed_wdays = Array(closed_wdays).map(&:to_i)
  end

  def regular_staff_days
    n
  end

  def hourly_staff_days
    (city_hall_days * 4 / 5.0).floor
  end

  def city_hall_days
    @city_hall_days ||= (@start_date..@end_date).count do |d|
      !d.saturday? && !d.sunday? && !@holidays.key?(d) && !year_end_new_year?(d)
    end
  end

  private

  def year_end_new_year?(date)
    YEAR_END_NEW_YEAR_MONTH_DAYS.include?([date.month, date.day])
  end

  def n
    @n ||= (@start_date..@end_date).count do |d|
      !@closed_wdays.include?(d.wday) && !@holidays.key?(d) && !year_end_new_year?(d)
    end
  end
end
