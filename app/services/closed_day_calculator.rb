class ClosedDayCalculator
  STATUTORY_CLOSURES = [[1, 4]].freeze

  def initialize(target_month, holidays)
    @start_date = target_month.beginning_of_month
    @end_date = target_month.end_of_month
    @holidays = holidays
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
    date.tuesday? || @holidays.key?(date) || statutory_closure?(date)
  end

  def statutory_closure?(date)
    STATUTORY_CLOSURES.any? { |m, d| date.month == m && date.day == d }
  end

  def label_for(date)
    if statutory_closure?(date)
      "条例休館日"
    elsif @holidays.key?(date)
      @holidays[date]
    else
      "定休日"
    end
  end
end
