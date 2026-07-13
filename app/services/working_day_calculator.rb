class WorkingDayCalculator
  def initialize(target_month, holidays, regular_closed_wday: 2)
    @start_date          = target_month.beginning_of_month
    @end_date            = target_month.end_of_month
    @holidays            = holidays
    @regular_closed_wday = regular_closed_wday
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
      (@start_date..@end_date).count do |d|
        !d.saturday? && !d.sunday? &&
          !@holidays.key?(d) &&
          (@regular_closed_wday.nil? || d.wday != @regular_closed_wday)
      end
    end
  end
end
