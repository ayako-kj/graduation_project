class SpecialDatesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_special_date, only: %i[edit update destroy]

  TARGET_GROUPS = %w[全職員 正規職員 専門司書 司書 行政職 一般事務].freeze

  def index
    @special_dates = SpecialDate.includes(:designated_staffs).order(:date)
  end

  def new
    @special_date = SpecialDate.new
    set_form_options
  end

  def create
    @special_date = SpecialDate.new(special_date_params)
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
    @special_date = SpecialDate.find(params[:id])
  end

  def set_form_options
    @staffs = Staff.includes(:staff_type).order(:name)
  end

  def sync_designated_staffs
    staff_ids = params.dig(:special_date, :designated_staff_ids)&.map(&:to_i) || []
    @special_date.designated_staffs = Staff.where(id: staff_ids)
  end

  def special_date_params
    params.require(:special_date).permit(:date, :label, :target_group)
  end
end
