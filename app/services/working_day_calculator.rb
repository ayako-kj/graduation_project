class WorkingDayCalculator
  def initialize(target_month, holidays)
    @start_date = target_month.beginning_of_month
    @end_date = target_month.end_of_month
    @holidays = holidays
  end

  def regular_staff_days
    n
  end

  def hourly_staff_days
    (n * 4 / 5.0).floor
  end

  private

  def n
    @n ||= begin
      weekdays = (@start_date..@end_date).count { |d| !d.saturday? && !d.sunday? }
      holidays_on_weekday = @holidays.keys.count { |d|
        d >= @start_date && d <= @end_date && !d.saturday? && !d.sunday?
      }
      weekdays - holidays_on_weekday
    end
  end
end
