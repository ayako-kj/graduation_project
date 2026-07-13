class WorkdayManualEntriesController < ApplicationController
  before_action :authenticate_admin!

  def index
    @target_month = parse_target_month
    @staffs = current_library.staffs.includes(:staff_type, :employment_type).order(:sort_order, :id)
    @entries_map = WorkdayManualEntry
      .where(staff: @staffs, year_month: @target_month)
      .index_by(&:staff_id)
  end

  def save
    @target_month = parse_target_month
    entries_params = params[:entries] || {}

    entries_params.each do |staff_id, data|
      days        = data[:working_days].presence&.to_i
      early       = data[:early_count].presence&.to_i
      post        = data[:post_duty_count].presence&.to_i
      holiday_post = data[:holiday_post_duty_count].presence&.to_i
      note        = data[:note].presence
      entry = WorkdayManualEntry.find_by(staff_id: staff_id.to_i, year_month: @target_month)

      if days.nil? && early.nil? && post.nil? && holiday_post.nil? && note.nil?
        entry&.destroy
        next
      end

      entry ||= WorkdayManualEntry.new(staff_id: staff_id.to_i, year_month: @target_month)
      entry.working_days             = days
      entry.early_count              = early
      entry.post_duty_count          = post
      entry.holiday_post_duty_count  = holiday_post
      entry.note                     = note
      entry.save!
    end

    redirect_to workday_manual_entries_path(month: @target_month.strftime("%Y-%m")),
                notice: "#{@target_month.strftime('%Y年%-m月')}の実績を保存しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to workday_manual_entries_path(month: @target_month.strftime("%Y-%m")),
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
