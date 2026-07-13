class ClosedDayCalculator
  # regular_closed_wday: 0=日 1=月 2=火 3=水 4=木 5=金 6=土、nilは定休曜日なし
  def initialize(target_month, holidays, regular_closed_wday: 2)
    @start_date          = target_month.beginning_of_month
    @end_date            = target_month.end_of_month
    @holidays            = holidays
    @regular_closed_wday = regular_closed_wday
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
    regular_closed?(date) || @holidays.key?(date)
  end

  def regular_closed?(date)
    @regular_closed_wday.present? && date.wday == @regular_closed_wday
  end

  def label_for(date)
    if @holidays.key?(date)
      @holidays[date]
    else
      "定休日"
    end
  end
end
