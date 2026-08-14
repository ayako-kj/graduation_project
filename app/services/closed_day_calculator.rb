class ClosedDayCalculator
  # closed_wdays: 0=日 1=月 2=火 3=水 4=木 5=金 6=土 の整数配列
  # extra_closed_dates: { date => label } の形式（臨時休館日）
  # forced_open_dates: { date => label } の形式（臨時開館日）。定休日・祝日・
  # 臨時休館日のいずれであっても、この日は休館日として扱わない
  def initialize(target_month, holidays, closed_wdays: [2], extra_closed_dates: {}, forced_open_dates: {})
    @start_date         = target_month.beginning_of_month
    @end_date           = target_month.end_of_month
    @holidays           = holidays
    @closed_wdays       = Array(closed_wdays).map(&:to_i)
    @extra_closed_dates = extra_closed_dates
    @forced_open_dates  = forced_open_dates
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
    return false if @forced_open_dates.key?(date)
    @closed_wdays.include?(date.wday) || regular_holiday?(date) || @extra_closed_dates.key?(date)
  end

  # 振替休日は開館日として扱う（振替休日以外の祝日のみ休館）
  def regular_holiday?(date)
    @holidays.key?(date) && !@holidays[date].include?("振替休日")
  end

  def label_for(date)
    return @holidays[date] if @holidays.key?(date)
    return @extra_closed_dates[date] if @extra_closed_dates.key?(date)
    "定休日"
  end
end
