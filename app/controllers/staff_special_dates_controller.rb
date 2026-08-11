class StaffSpecialDatesController < ApplicationController
  before_action :authenticate_staff_token!
  before_action :set_special_date, only: %i[edit update destroy]
  before_action :authorize_own!, only: %i[edit update destroy]

  def index
    @target_month  = parse_target_month
    @special_date  = SpecialDate.new(date: @target_month.beginning_of_month)
    @special_dates = @current_staff.library.special_dates
                       .includes(:created_by_staff, :designated_staffs)
                       .where(date: @target_month.beginning_of_month..@target_month.end_of_month)
                       .order(:date)
    @input_deadline = @current_staff.library.input_deadlines.find_by(target_month: @target_month.beginning_of_month)
    @submission = MonthlySubmission.find_by(staff: @current_staff, target_month: @target_month.beginning_of_month)
    load_form_data
  end

  def create
    @special_date = SpecialDate.new(special_date_params)
    @special_date.library              = @current_staff.library
    @special_date.created_by_staff_id = @current_staff.id

    if @special_date.save
      sync_designated_staffs
      reset_schedule_submission!(@special_date.date)
      redirect_to staff_special_dates_path(token: params[:token], month: params[:month]),
                  notice: "スケジュールを登録しました。"
    else
      @target_month  = parse_target_month
      @special_dates = @current_staff.library.special_dates
                         .includes(:created_by_staff, :designated_staffs)
                         .where(date: @target_month.beginning_of_month..@target_month.end_of_month)
                         .order(:date)
      @input_deadline = @current_staff.library.input_deadlines.find_by(target_month: @target_month.beginning_of_month)
      @submission = MonthlySubmission.find_by(staff: @current_staff, target_month: @target_month.beginning_of_month)
      load_form_data
      render :index, status: :unprocessable_entity
    end
  end

  def edit
    @target_month = parse_target_month
    load_form_data
  end

  def update
    if @special_date.update(special_date_params)
      sync_designated_staffs
      reset_schedule_submission!(@special_date.date)
      redirect_to staff_special_dates_path(token: params[:token], month: params[:month]),
                  notice: "スケジュールを更新しました。"
    else
      @target_month = parse_target_month
      load_form_data
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    date = @special_date.date
    @special_date.destroy
    reset_schedule_submission!(date)
    redirect_to staff_special_dates_path(token: params[:token], month: params[:month]),
                notice: "スケジュールを削除しました。"
  end

  def complete
    @target_month = parse_target_month
    submission = MonthlySubmission.find_or_initialize_by(staff: @current_staff, target_month: @target_month)
    submission.schedule_submitted_at = Time.current
    submission.save!

    has_entries = @current_staff.library.special_dates.where(
      date: @target_month.beginning_of_month..@target_month.end_of_month,
      created_by_staff_id: @current_staff.id
    ).exists?

    redirect_to staff_special_dates_path(token: params[:token], month: @target_month.strftime("%Y-%m")),
                notice: has_entries ? "スケジュール登録が完了しました。" : "登録するスケジュールがありません。"
  end

  private

  def reset_schedule_submission!(date)
    MonthlySubmission.find_by(staff: @current_staff, target_month: date.beginning_of_month)
                      &.update(schedule_submitted_at: nil)
  end

  def authenticate_staff_token!
    @current_staff = Staff.find_by(access_token: params[:token])
    return if @current_staff

    render plain: "アクセストークンが無効です。配布されたURLを確認してください。", status: :unauthorized
  end

  def set_special_date
    @special_date = SpecialDate.find(params[:id])
  end

  def authorize_own!
    unless @special_date.created_by_staff_id == @current_staff.id
      redirect_to staff_special_dates_path(token: params[:token], month: params[:month]),
                  alert: "自分が登録したスケジュールのみ編集・削除できます。"
    end
  end

  def load_form_data
    @staffs      = @current_staff.library.staffs.includes(:staff_type).order(:sort_order, :id)
    @assignments = @current_staff.library.assignments.includes(:staffs).order(:id)
  end

  def sync_designated_staffs
    staff_ids = params.dig(:special_date, :designated_staff_ids)&.map(&:to_i) || []
    @special_date.designated_staffs = Staff.where(id: staff_ids)
  end

  def special_date_params
    params.require(:special_date).permit(:date, :label, :target_group)
  end

  def parse_target_month
    if params[:month].present?
      Date.parse("#{params[:month]}-01")
    else
      Date.today.beginning_of_month.next_month
    end
  rescue ArgumentError, TypeError
    Date.today.beginning_of_month.next_month
  end
end
