class SpecialDatesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_special_date, only: %i[edit update destroy]

  TARGET_GROUPS = SpecialDate::TARGET_GROUPS

  def index
    @target_month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.today.beginning_of_month.next_month
    @special_dates = current_library.special_dates
                       .includes(:designated_staffs, :created_by_staff)
                       .where(date: @target_month.beginning_of_month..@target_month.end_of_month)
                       .order(:date)
  end

  def new
    @special_date = current_library.special_dates.build(date: Date.today.beginning_of_month.next_month)
    set_form_options
  end

  def create
    @special_date = current_library.special_dates.build(special_date_params)
    @special_date.designated_staff_ids_input = designated_staff_ids_param
    if @special_date.save
      sync_designated_staffs
      redirect_to special_dates_path(month: @special_date.date.strftime("%Y-%m")), notice: "スケジュールを登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    @special_date.designated_staff_ids_input = designated_staff_ids_param
    if @special_date.update(special_date_params)
      sync_designated_staffs
      redirect_to special_dates_path(month: @special_date.date.strftime("%Y-%m")), notice: "スケジュールを更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @special_date.destroy
    redirect_to special_dates_path(month: @special_date.date.strftime("%Y-%m")), notice: "#{@special_date.label}を削除しました。"
  end

  private

  def set_special_date
    @special_date = current_library.special_dates.find(params[:id])
  end

  def set_form_options
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    @assignments = current_library.assignments.includes(:staffs).order(:id)
  end

  def sync_designated_staffs
    @special_date.designated_staffs = Staff.where(id: designated_staff_ids_param.map(&:to_i))
  end

  def designated_staff_ids_param
    Array(params.dig(:special_date, :designated_staff_ids)).reject(&:blank?)
  end

  def special_date_params
    params.require(:special_date).permit(:date, :label, :target_group)
  end
end
