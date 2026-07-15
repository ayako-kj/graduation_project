class SpecialDatesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_special_date, only: %i[edit update destroy]

  TARGET_GROUPS = %w[全職員 正規職員 専門司書 司書 行政職 一般事務].freeze

  def index
    @target_month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.today.beginning_of_month
    @special_dates = current_library.special_dates
                       .includes(:designated_staffs)
                       .where(date: @target_month.beginning_of_month..@target_month.end_of_month)
                       .order(:date)
  end

  def new
    @special_date = current_library.special_dates.build
    set_form_options
  end

  def create
    @special_date = current_library.special_dates.build(special_date_params)
    if @special_date.save
      sync_designated_staffs
      redirect_to special_dates_path, notice: "特定日を登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    if @special_date.update(special_date_params)
      sync_designated_staffs
      redirect_to special_dates_path, notice: "特定日を更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @special_date.destroy
    redirect_to special_dates_path, notice: "#{@special_date.label}を削除しました。"
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
    staff_ids = params.dig(:special_date, :designated_staff_ids)&.map(&:to_i) || []
    @special_date.designated_staffs = Staff.where(id: staff_ids)
  end

  def special_date_params
    params.require(:special_date).permit(:date, :label, :target_group)
  end
end
