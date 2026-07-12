class ActualLeavesController < ApplicationController
  before_action :authenticate_admin!

  def index
    @target_month = parse_target_month
    @staffs = current_library.staffs.includes(:staff_type, :employment_type).order(:sort_order, :id)

    holidays = HolidayFetcher.fetch(@target_month.year)
    closed = ClosedDayCalculator.new(@target_month, holidays).closed_days_with_labels
    @open_dates = (@target_month.beginning_of_month..@target_month.end_of_month)
                    .reject { |d| closed.key?(d) }

    sg = current_library.shift_groups.find_by(target_month: @target_month)
    @shift_map = {}
    if sg
      Shift.where(shift_group: sg).each do |s|
        @shift_map[[s.staff_id, s.date]] = s
      end
    end

    @leave_map = ActualLeave
      .where(staff: @staffs, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .index_by { |l| [l.staff_id, l.date] }
  end

  def save
    @target_month = parse_target_month
    start_date = @target_month.beginning_of_month
    end_date   = @target_month.end_of_month

    entries = params[:leaves] || {}
    ActualLeave.transaction do
      # 対象月の既存レコードを一括削除して保存し直す
      staff_ids = current_library.staffs.pluck(:id)
      ActualLeave.where(staff_id: staff_ids, date: start_date..end_date).delete_all

      entries.each do |staff_id, dates|
        dates.each do |date_str, leave_type|
          next if leave_type.blank? || !ActualLeave::LEAVE_TYPES.key?(leave_type)
          ActualLeave.create!(
            staff_id: staff_id.to_i,
            date: Date.parse(date_str),
            leave_type: leave_type
          )
        end
      end
    end

    redirect_to actual_leaves_path(month: @target_month.strftime("%Y-%m")),
                notice: "#{@target_month.strftime('%Y年%-m月')}の休暇種別を保存しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to actual_leaves_path(month: @target_month.strftime("%Y-%m")),
                alert: "保存に失敗しました：#{e.message}"
  end

  private

  def parse_target_month
    if params[:month].present?
      Date.parse("#{params[:month]}-01")
    else
      Date.today.beginning_of_month
    end
  rescue Date::Error
    Date.today.beginning_of_month
  end
end
