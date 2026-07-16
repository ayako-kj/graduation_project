class ClosedDayCalculator
  # closed_wdays: 0=日 1=月 2=火 3=水 4=木 5=金 6=土 の整数配列
  # extra_closed_dates: { date => label } の形式（臨時休館日）
  def initialize(target_month, holidays, closed_wdays: [2], extra_closed_dates: {})
    @start_date         = target_month.beginning_of_month
    @end_date           = target_month.end_of_month
    @holidays           = holidays
    @closed_wdays       = Array(closed_wdays).map(&:to_i)
    @extra_closed_dates = extra_closed_dates
  end

  def closed_days
    (@start_date..@end_date).select { |date| closed?(date) }
  end

  def closed_days_with_labels
    (@start_date..@end_date).each_with_object({}) do |date, hash|
      next unless closed?(date)
      hash[date] = label_for(date)
    end
  end

  private

  def closed?(date)
    @closed_wdays.include?(date.wday) || @holidays.key?(date) || @extra_closed_dates.key?(date)
  end

  def label_for(date)
    return @holidays[date] if @holidays.key?(date)
    return @extra_closed_dates[date] if @extra_closed_dates.key?(date)
    "定休日"
  end
end
