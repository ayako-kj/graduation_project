class WorkingDayCalculator
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
    (n * 4 / 5.0).floor
  end

  private

  def n
    @n ||= (@start_date..@end_date).count do |d|
      !d.saturday? && !d.sunday? && !@holidays.key?(d) && !@closed_wdays.include?(d.wday)
    end
  end
end
